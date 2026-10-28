USE mdb;
SET NOCOUNT ON;

/*
================================================================================
COI - ENCERRADOS pelo COI por HORA do dia, consolidado por mes
================================================================================

Mostra EM QUE HORA DO DIA o COI encerra chamados: a distribuicao pela hora da
DATA DE ENCERRAMENTO (call_req.close_date), em horario do Brasil.

Saida: UM unico result set.
    Ano, Mes, MesAno, Hora, HoraLabel, QtdEncerrados

    - uma linha para CADA combinacao de mes e hora do periodo: 24 linhas por
      mes, de 00h a 23h, inclusive as horas sem encerramento;
    - dentro de um mes, todos os dias sao somados na mesma hora;
    - as 24 horas de um mes somam o total de Encerrados daquele mes em
      consulta_coi_encerrados.sql, para o mesmo periodo e o mesmo grupo alvo.

    E a contrapartida de consulta_coi_registrados_por_hora.sql, que faz o mesmo
    com a hora da DataRegistroCOI. As duas tem as mesmas colunas de mes e hora
    para serem lidas lado a lado; as POPULACOES sao diferentes (ver abaixo).

A REGRA DE ENCERRADOS NAO E NOVA

    A populacao vem, LITERALMENTE, de queries/consulta_coi_encerrados.sql,
    inclusive a validacao do grupo alvo:

        close_date >= @DataInicio  e  < @DataFim   (semiaberto)
        type       IN ('I','R')
        status     IN ('CL','CLUNRSLV')
        group_id   =  @COI_GrupoAlvo               (UM grupo, nunca dois)
        e o grupo alvo precisa existir, estar ativo e ter ao menos um membro

    O eixo e a DATA DE ENCERRAMENTO. NAO e a DataRegistroCOI: registrar e
    encerrar sao movimentacoes diferentes, com populacoes diferentes. A hora de
    registro nunca e usada aqui.

HORA
    DATEPART(HOUR, ...) sobre close_date ja convertido para o horario do Brasil
    (UTC-3 fixo). 00h = encerramentos entre 00:00:00 e 00:59:59, e assim por
    diante.

Somente leitura. Batch unico, sem GO.
================================================================================
*/

--------------------------------------------------------------------------------
-- [0] PARAMETROS
--------------------------------------------------------------------------------

-- Periodo em horario do Brasil, intervalo SEMIABERTO: >= inicio e < fim.
-- Nunca usar 23:59:59 como fim: o chamado fechado no ultimo segundo do dia
-- ficaria de fora.
DECLARE @DataInicio datetime2(0) = '2026-09-01 00:00:00';   -- inclusivo
DECLARE @DataFim    datetime2(0) = '2026-10-01 00:00:00';   -- EXCLUSIVO

-- Identidade do COI. SEMPRE por UUID: nome de grupo muda, UUID nao.
DECLARE @COI_Antigo varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;  -- 'Contrato 7/2023 - COI'
DECLARE @COI_Novo   varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;  -- 'COI'

-- Grupo alvo da apuracao: UM grupo, declarado por quem apura (ver o cabecalho de
-- consulta_coi_encerrados.sql). Producao / contrato vigente -> @COI_Novo.
-- NAO somar os dois e NAO escolher pela data: os grupos coexistiram.
DECLARE @COI_GrupoAlvo varbinary(16) = @COI_Novo;

DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';
DECLARE @IniEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @DataInicio));
DECLARE @FimEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @DataFim));

--------------------------------------------------------------------------------
-- [1] VALIDACAO DO GRUPO ALVO - identica a de consulta_coi_encerrados.sql.
--------------------------------------------------------------------------------
DECLARE @GrupoNome     nvarchar(200);
DECLARE @GrupoInativo  int;
DECLARE @GrupoMembros  bigint;

SELECT
    @GrupoNome    = LTRIM(RTRIM(COALESCE(NULLIF(c.last_name, N''), NULLIF(c.userid, N''), N'(sem nome)'))),
    @GrupoInativo = c.inactive
FROM dbo.ca_contact AS c
WHERE c.contact_uuid = @COI_GrupoAlvo;

SELECT @GrupoMembros = COUNT_BIG(*)
FROM dbo.grpmem AS gm
WHERE gm.group_id = @COI_GrupoAlvo;

DECLARE @GrupoAlvoValido bit =
    CASE WHEN @GrupoNome IS NOT NULL AND @GrupoInativo = 0 AND @GrupoMembros > 0
         THEN 1 ELSE 0 END;

IF @GrupoAlvoValido = 0
    PRINT N'ATENCAO: o grupo alvo NAO passa no filtro da Consulta para Auditoria '
        + N'(precisa existir, estar com inactive = 0 e ter ao menos um membro em grpmem). '
        + N'O resultado sera ZERO em todas as horas por causa disso, e nao por ausencia de encerramentos.';

--------------------------------------------------------------------------------
-- [2] POPULACAO - Encerrados pelo COI. A regra inteira mora neste WHERE, e e a
--     de consulta_coi_encerrados.sql sem alteracao.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#EncerradosCOI') IS NOT NULL DROP TABLE #EncerradosCOI;

SELECT
    r.id,
    r.ref_num AS SDM,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.close_date, @Epoch)) AS encerramento_br
INTO #EncerradosCOI
FROM dbo.call_req AS r
WHERE r.close_date >= @IniEpoch
  AND r.close_date <  @FimEpoch
  AND r.[type]   IN ('I', 'R')
  AND r.status   IN ('CL', 'CLUNRSLV')
  AND r.group_id = @COI_GrupoAlvo
  AND @GrupoAlvoValido = 1
OPTION (RECOMPILE);

CREATE UNIQUE CLUSTERED INDEX IX_EncerradosCOI ON #EncerradosCOI(id);

--------------------------------------------------------------------------------
-- [C] CALENDARIO - todos os meses do periodo x as 24 horas, inclusive as de
--     quantidade zero. Mesma construcao de consulta_coi_registrados_por_hora.sql:
--     MesAno sai como AAAA-MM, que nao depende do idioma do servidor e ordena
--     corretamente como texto.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Dias') IS NOT NULL DROP TABLE #Dias;

SELECT TOP (DATEDIFF(DAY, @DataInicio, @DataFim))
    CONVERT(date, DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, @DataInicio)) AS dia
INTO #Dias
FROM sys.all_objects AS a
CROSS JOIN sys.all_objects AS b;

CREATE UNIQUE CLUSTERED INDEX IX_Dias ON #Dias(dia);

IF OBJECT_ID('tempdb..#Meses') IS NOT NULL DROP TABLE #Meses;

SELECT DISTINCT
    YEAR(d.dia)  AS Ano,
    MONTH(d.dia) AS Mes,
    CONVERT(char(7), CONCAT(YEAR(d.dia), N'-', RIGHT(CONCAT(N'0', MONTH(d.dia)), 2))) AS MesAno
INTO #Meses
FROM #Dias AS d;

CREATE UNIQUE CLUSTERED INDEX IX_Meses ON #Meses(Ano, Mes);

IF OBJECT_ID('tempdb..#Horas') IS NOT NULL DROP TABLE #Horas;

SELECT TOP (24)
    CONVERT(int, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1) AS Hora
INTO #Horas
FROM sys.all_objects AS a;

CREATE UNIQUE CLUSTERED INDEX IX_Horas ON #Horas(Hora);

--------------------------------------------------------------------------------
-- RESULTADO - Encerrados pelo COI por hora, consolidado por mes
--
-- Cada encerrado cai em exatamente UMA celula (mes, hora): #EncerradosCOI tem
-- uma linha por chamado (indice UNICO por id) e a celula e funcao do instante
-- de encerramento. Por isso as 24 horas de um mes somam o total do mes.
--------------------------------------------------------------------------------
SELECT
    m.Ano,
    m.Mes,
    m.MesAno,
    h.Hora,
    CONVERT(char(3), CONCAT(RIGHT(CONCAT(N'0', h.Hora), 2), N'h')) AS HoraLabel,
    ISNULL(agg.Qtd, 0) AS QtdEncerrados
FROM #Meses AS m
CROSS JOIN #Horas AS h
OUTER APPLY (
    SELECT COUNT(*) AS Qtd
    FROM #EncerradosCOI AS e
    WHERE YEAR(e.encerramento_br)           = m.Ano
      AND MONTH(e.encerramento_br)          = m.Mes
      AND DATEPART(HOUR, e.encerramento_br) = h.Hora
) AS agg
ORDER BY
    m.Ano,
    m.Mes,
    h.Hora;
