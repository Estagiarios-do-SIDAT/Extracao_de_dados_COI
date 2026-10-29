USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- VERSAO POWER BI de queries/consulta_coi_pesquisa_satisfacao_encerrados_detalhe.sql
--
-- A regra e a da consulta de /queries, que e a fonte de verdade. Este arquivo
-- e o texto dela sem alteracao, exceto pelas adaptacoes abaixo, marcadas no
-- corpo com [POWER BI]. Se esta versao e a fonte divergirem, vale a fonte.
--
-- Adaptacoes:
--   - periodo automatico: os meses de calendario COMPLETOS anteriores ao mes
--     corrente - ate @PBI_QuantidadeMeses, a partir de @PBI_InicioMinimoBR -,
--     no lugar das datas digitadas;
--   - saida: a fonte ja devolve um unico result set, que sai sem alteracao.
--
-- Power BI: conector SQL Server, banco mdb, modo Importacao, este arquivo
-- inteiro no campo Instrucao SQL, Adicionar colunas de relacao desmarcado.
-- Somente leitura. Batch unico, sem GO.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- [POWER BI] PERIODO AUTOMATICO
--
-- A fonte recebe o periodo digitado, em meses de calendario com fim EXCLUSIVO.
-- Aqui ele e calculado a cada atualizacao, na mesma forma:
--
--     fim    (exclusivo) = dia 1 do mes corrente, 00:00:00, horario do Brasil
--     inicio (inclusivo) = @PBI_QuantidadeMeses meses antes do fim, mas nunca
--                          antes de @PBI_InicioMinimoBR
--
-- Entram so meses COMPLETOS: o mes em andamento fica de fora. As consultas do
-- painel usam todas este MESMO periodo, para que o filtro Mes/Ano enxergue os
-- mesmos meses em todas as paginas.
--
-- @PBI_InicioMinimoBR = 01/03/2026: mes em que o novo COI passou a usar o
-- codigo de fornecedor atual, o grupo alvo de Encerrados (@COI_Novo). Marco
-- entra INTEIRO. Antes dele, os encerramentos sao do grupo antigo - outro
-- contrato, que a regra de Encerrados nao soma -, e o painel mostraria meses
-- sem Encerrados ao lado de meses com Registrados. O piso so muda se mudar o
-- grupo alvo.
--
-- @PBI_QuantidadeMeses vem do parametro QtdMesesCompletosCOI do Power Query,
-- o MESMO nas seis consultas. O Power Query troca o 12 da linha abaixo pela
-- referencia @QtdMesesCompletosCOI e executa o lote com esse parametro SQL
-- (Value.NativeQuery, sp_executesql); ver powerbi/powerbi-query.md, secao 3.
-- O 12 vale so quando o arquivo roda fora do Power BI. Nao mude o texto da
-- linha: o Power Query a localiza por ele e falha se nao a encontrar.
--------------------------------------------------------------------------------
DECLARE @PBI_QuantidadeMeses int = 12;
DECLARE @PBI_InicioMinimoBR datetime2(0) = '2026-03-01 00:00:00';

IF @PBI_QuantidadeMeses IS NULL OR @PBI_QuantidadeMeses < 1
    THROW 50001, N'[POWER BI] QtdMesesCompletosCOI deve ser um inteiro positivo.', 1;

DECLARE @PBI_HojeBR date =
    CONVERT(date, DATEADD(HOUR, -3, SYSUTCDATETIME()));
DECLARE @PBI_FimBR datetime2(0) =
    CONVERT(datetime2(0), DATEFROMPARTS(YEAR(@PBI_HojeBR), MONTH(@PBI_HojeBR), 1));
-- Fim e piso sao dias 1: "n meses antes do fim depois do piso" equivale a
-- "n menor que os meses entre piso e fim", e esta forma nao estoura o
-- DATEADD quando n e muito grande.
DECLARE @PBI_InicioBR datetime2(0) =
    CASE WHEN @PBI_QuantidadeMeses < DATEDIFF(MONTH, @PBI_InicioMinimoBR, @PBI_FimBR)
         THEN DATEADD(MONTH, -@PBI_QuantidadeMeses, @PBI_FimBR)
         ELSE @PBI_InicioMinimoBR END;


/*
================================================================================
COI - PESQUISA DE SATISFACAO DOS ENCERRADOS - detalhe, uma linha por SDM
================================================================================

Saida: UM unico result set, UMA linha por chamado ENCERRADO pelo COI no periodo.

    SDM, TipoChamado, DataEncerramento, Ano, Mes, MesAno,
    StatusSatisfacao, PerguntaAvaliada, RespostaSatisfacao,
    QtdPerguntasRespondidas, DataPesquisa,
    PesquisaSolicitada, QtdSolicitacoesPesquisa, DataSolicitacaoPesquisa,
    SolicitacaoPesquisa

POR QUE ESTA CONSULTA EXISTE

    consulta_coi_pesquisa_satisfacao_encerrados.sql responde a mesma pergunta em
    duas janelas: um resumo (Com x Sem satisfacao) e uma lista dos SDMs com a
    opcao escolhida. Nenhuma das duas traz DATA, e o resumo e agregado. Um
    painel filtrado por Mes/Ano nao consegue usar nenhuma delas. Esta consulta
    entrega a MESMA classificacao, chamado a chamado, com a data de encerramento
    - o resumo e a lista da consulta original sao agrupamentos desta saida.

A REGRA NAO E NOVA

    Populacao: os Encerrados pelo COI, LITERALMENTE como em
    consulta_coi_encerrados.sql e consulta_coi_pesquisa_satisfacao_encerrados.sql:

        close_date >= @DataInicio  e  < @DataFim   (semiaberto)
        type       IN ('I','R')
        status     IN ('CL','CLUNRSLV')
        group_id   =  @COI_GrupoAlvo               (UM grupo, nunca dois)
        e o grupo alvo precisa existir, estar ativo e ter ao menos um membro

    Pesquisa, resposta e classificacao: os passos [3] a [5] de
    consulta_coi_pesquisa_satisfacao_encerrados.sql, sem alteracao:

        - uma pesquisa por chamado: a MAIS RECENTE (last_mod_dt desc, id desc),
          sem as excluidas (del = 0);
        - "Com satisfacao" = a pesquisa tem ao menos UMA opcao selecionada, em
          qualquer pergunta; senao "Sem satisfacao";
        - RespostaSatisfacao = a opcao selecionada na pergunta de ordem
          @SequenciaPerguntaAvaliada (padrao 40, satisfacao geral com a execucao
          dos servicos); NULL quando essa pergunta ficou em branco.

    Equivalencia com a consulta original, para o mesmo periodo e grupo:
        contagem por StatusSatisfacao ............... = Janela 1
        linhas com RespostaSatisfacao preenchida ... = Janela 2

COLUNAS DE SOLICITACAO DA PESQUISA - informativas, fora da classificacao

    O SDM registra em dbo.act_log um evento SRVY_SENT ("Solicitacao de pesquisa
    (...) enviada para ...") quando dispara o pedido de pesquisa. Ele NAO cria,
    por si, uma instancia em dbo.survey: na medicao de 01/04/2026 a 01/10/2026
    (grupo COI_Novo), 2.242 dos 3.558 encerrados tem SRVY_SENT e so 2 tem
    pesquisa em dbo.survey, ambas respondidas.

    Por isso ha duas leituras possiveis de "quantidade de pesquisas", e as duas
    ficam visiveis, sem misturar:

        PesquisaSolicitada = 'Sim'          pedido de pesquisa registrado pelo SDM
        StatusSatisfacao = 'Com satisfação' pesquisa existente e respondida
                                            (a regra validada do COI)

    PesquisaSolicitada, QtdSolicitacoesPesquisa, DataSolicitacaoPesquisa e
    SolicitacaoPesquisa NAO mudam StatusSatisfacao nem RespostaSatisfacao.

DATAS
    DataEncerramento ......... close_date em horario do Brasil (eixo do periodo)
    DataPesquisa ............. last_mod_dt da pesquisa considerada; NULL sem
                               pesquisa
    DataSolicitacaoPesquisa .. o SRVY_SENT mais recente do chamado; NULL sem
                               solicitacao
    Ano, Mes, MesAno ......... da DataEncerramento; MesAno = AAAA-MM, que nao
                               depende do idioma do servidor

DUPLICIDADE
    Uma linha por chamado, por construcao: a populacao sai de UMA passagem em
    call_req; #Pesquisa e #Satisfacao tem indice UNICO por chamado; as
    solicitacoes entram por #Solicitacao, tambem com indice UNICO por
    chamado.

Somente leitura. Batch unico, sem GO.
================================================================================
*/

--------------------------------------------------------------------------------
-- [0] PARAMETROS
--------------------------------------------------------------------------------

-- Periodo em horario do Brasil, intervalo SEMIABERTO: >= inicio e < fim.
-- O fim e o PRIMEIRO INSTANTE DE FORA. Nunca usar 23:59:59.
-- [POWER BI] Periodo automatico, calculado no inicio do arquivo.
DECLARE @DataInicio datetime2(0) = @PBI_InicioBR;   -- inclusivo
DECLARE @DataFim    datetime2(0) = @PBI_FimBR;      -- EXCLUSIVO

-- Identidade do COI. SEMPRE por UUID: nome de grupo muda, UUID nao.
DECLARE @COI_Antigo varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;  -- 'Contrato 7/2023 - COI'
DECLARE @COI_Novo   varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;  -- 'COI'

-- GRUPO ALVO: a unica linha que decide QUAL contrato esta sendo apurado.
--     producao / contrato vigente ............... @COI_Novo
--     conferencia do RSP de fevereiro/2026 ...... @COI_Antigo
-- NAO combinar os dois. NAO escolher automaticamente pela data.
DECLARE @COI_GrupoAlvo varbinary(16) = @COI_Novo;

-- Qual pergunta da pesquisa vira a RespostaSatisfacao.
--   10 = O problema foi resolvido?            (Sim / Nao)
--   20 = Atendimento telefonico / teleoperador
--   30 = Atendimento do tecnico presencial
--   40 = Satisfacao GERAL com a execucao dos servicos   <-- padrao
--   50 = Satisfacao GERAL com o tempo de atendimento
DECLARE @SequenciaPerguntaAvaliada int = 40;

DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';
DECLARE @IniEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @DataInicio));
DECLARE @FimEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @DataFim));

--------------------------------------------------------------------------------
-- [1] VALIDACAO DO GRUPO ALVO - identica a de consulta_coi_encerrados.sql.
--------------------------------------------------------------------------------
DECLARE @GrupoNome    nvarchar(200);
DECLARE @GrupoInativo int;
DECLARE @GrupoMembros bigint;

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
        + N'O resultado sera VAZIO por causa disso, e nao por ausencia de encerramentos.';

--------------------------------------------------------------------------------
-- [2] POPULACAO - Encerrados pelo COI. O WHERE e o de consulta_coi_encerrados.sql
--     sem acrescimo nem supressao. persid e lido so para localizar o SRVY_SENT
--     em act_log; nao participa de filtro.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#EncerradosCOI') IS NOT NULL DROP TABLE #EncerradosCOI;

SELECT
    r.id,
    r.persid,
    r.ref_num AS SDM,
    r.[type]  AS tipo,
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
-- [3] UMA pesquisa por chamado: a mais recente. Igual a consulta original.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Pesquisa') IS NOT NULL DROP TABLE #Pesquisa;

SELECT z.survey_id, z.call_req_id, z.last_mod_dt
INTO #Pesquisa
FROM (
    SELECT s.id AS survey_id, s.object_id AS call_req_id, s.last_mod_dt,
           ROW_NUMBER() OVER (PARTITION BY s.object_id
                              ORDER BY s.last_mod_dt DESC, s.id DESC) AS rn
    FROM dbo.survey AS s
    JOIN #EncerradosCOI AS e ON e.id = s.object_id
    WHERE s.object_type = N'cr'
      AND s.del = 0
) AS z
WHERE z.rn = 1;

CREATE UNIQUE CLUSTERED INDEX IX_Pesquisa ON #Pesquisa(call_req_id);

--------------------------------------------------------------------------------
-- [4] O que o usuario selecionou. Igual a consulta original.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Satisfacao') IS NOT NULL DROP TABLE #Satisfacao;

SELECT
    p.call_req_id,
    p.survey_id,
    p.last_mod_dt,
    sel.qtd_opcoes_selecionadas,
    CONVERT(nvarchar(200), alvo.txt) AS resposta_avaliada
INTO #Satisfacao
FROM #Pesquisa AS p
CROSS APPLY (
    SELECT qtd_opcoes_selecionadas = COUNT(*)
    FROM dbo.survey_question AS q
    JOIN dbo.survey_answer AS a
        ON a.own_srvy_question = q.id
       AND a.selected = 1
    WHERE q.owning_survey = p.survey_id
) AS sel
OUTER APPLY (
    SELECT TOP (1) a2.txt
    FROM dbo.survey_question AS q2
    JOIN dbo.survey_answer AS a2
        ON a2.own_srvy_question = q2.id
       AND a2.selected = 1
    WHERE q2.owning_survey = p.survey_id
      AND q2.sequence = @SequenciaPerguntaAvaliada
    ORDER BY a2.sequence, a2.id
) AS alvo;

CREATE UNIQUE CLUSTERED INDEX IX_Satisfacao ON #Satisfacao(call_req_id);

--------------------------------------------------------------------------------
-- [5] SOLICITACAO DE PESQUISA - os eventos SRVY_SENT do proprio chamado em
--     act_log (call_req_id = persid), lidos UMA vez para a populacao inteira.
--     Fica uma linha por chamado: a contagem de todos e o mais recente, com
--     desempate system_time desc, id desc (o id e a ordem de gravacao no SDM).
--     Indice UNICO: se a premissa falhar, a criacao do indice falha em vez de
--     multiplicar o chamado no resultado.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Solicitacao') IS NOT NULL DROP TABLE #Solicitacao;

SELECT z.id, z.qtd, z.system_time, z.texto
INTO #Solicitacao
FROM (
    SELECT
        e.id,
        al.system_time,
        LTRIM(RTRIM(CONVERT(nvarchar(400), al.[description]))) AS texto,
        COUNT(*) OVER (PARTITION BY e.id) AS qtd,
        ROW_NUMBER() OVER (PARTITION BY e.id ORDER BY al.system_time DESC, al.id DESC) AS rn
    FROM #EncerradosCOI AS e
    JOIN dbo.act_log AS al
        ON al.call_req_id = e.persid
    WHERE al.[type] = 'SRVY_SENT'
) AS z
WHERE z.rn = 1;

CREATE UNIQUE CLUSTERED INDEX IX_Solicitacao ON #Solicitacao(id);

--------------------------------------------------------------------------------
-- RESULTADO - uma linha por chamado encerrado pelo COI
--
-- #Satisfacao e #Solicitacao tem indice UNICO por chamado: os LEFT JOIN nao
-- multiplicam linha e nao removem chamado sem pesquisa ou sem solicitacao.
--------------------------------------------------------------------------------
SELECT
    e.SDM,
    CASE e.tipo WHEN 'I' THEN N'Incidente'
                WHEN 'R' THEN N'Solicitação'
                ELSE N'N/A' END                                          AS TipoChamado,
    e.encerramento_br                                                    AS DataEncerramento,
    YEAR(e.encerramento_br)                                              AS Ano,
    MONTH(e.encerramento_br)                                             AS Mes,
    CONVERT(char(7), CONCAT(YEAR(e.encerramento_br), N'-',
            RIGHT(CONCAT(N'0', MONTH(e.encerramento_br)), 2)))           AS MesAno,
    CONVERT(nvarchar(20), CASE WHEN ISNULL(s.qtd_opcoes_selecionadas, 0) > 0
                               THEN N'Com satisfação'
                               ELSE N'Sem satisfação' END)              AS StatusSatisfacao,
    @SequenciaPerguntaAvaliada                                           AS PerguntaAvaliada,
    s.resposta_avaliada                                                  AS RespostaSatisfacao,
    ISNULL(s.qtd_opcoes_selecionadas, 0)                                 AS QtdPerguntasRespondidas,
    CASE WHEN s.last_mod_dt IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, s.last_mod_dt, @Epoch))
    END                                                                  AS DataPesquisa,
    CASE WHEN ISNULL(sol.qtd, 0) > 0 THEN N'Sim' ELSE N'Não' END         AS PesquisaSolicitada,
    ISNULL(sol.qtd, 0)                                                   AS QtdSolicitacoesPesquisa,
    CASE WHEN sol.system_time IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, sol.system_time, @Epoch))
    END                                                                  AS DataSolicitacaoPesquisa,
    sol.texto                                                            AS SolicitacaoPesquisa
FROM #EncerradosCOI AS e
LEFT JOIN #Satisfacao AS s
    ON s.call_req_id = e.id
LEFT JOIN #Solicitacao AS sol
    ON sol.id = e.id
ORDER BY
    e.encerramento_br,
    e.SDM;
