USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- VERSAO POWER BI de queries/consulta_coi_encerrados.sql
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
-- sem Encerrados ao lado de meses com Registrados. Para mudar a cobertura,
-- altere apenas @PBI_QuantidadeMeses; o piso so muda se mudar o grupo alvo.
--------------------------------------------------------------------------------
DECLARE @PBI_QuantidadeMeses int = 12;
DECLARE @PBI_InicioMinimoBR datetime2(0) = '2026-03-01 00:00:00';

DECLARE @PBI_HojeBR date =
    CONVERT(date, DATEADD(HOUR, -3, SYSUTCDATETIME()));
DECLARE @PBI_FimBR datetime2(0) =
    CONVERT(datetime2(0), DATEFROMPARTS(YEAR(@PBI_HojeBR), MONTH(@PBI_HojeBR), 1));
DECLARE @PBI_InicioBR datetime2(0) =
    CASE WHEN DATEADD(MONTH, -@PBI_QuantidadeMeses, @PBI_FimBR) > @PBI_InicioMinimoBR
         THEN DATEADD(MONTH, -@PBI_QuantidadeMeses, @PBI_FimBR)
         ELSE @PBI_InicioMinimoBR END;


/*
================================================================================
COI - Chamados ENCERRADOS pelo COI
================================================================================

REGRA IMPLEMENTADA

    Encerrado pelo COI = chamado do GRUPO ALVO da apuracao, do tipo Incidente ou
    Solicitacao, com status CL ou CLUNRSLV, cujo close_date cai no periodo
    analisado.

        close_date  >= @DataInicio  e  <  @DataFim   (semiaberto)
        type        IN ('I','R')
        status      IN ('CL','CLUNRSLV')
        group_id    =  @COI_GrupoAlvo                (UM grupo, nunca dois)

    E a regra da "Consulta para Auditoria", que e o instrumento com que o
    fornecedor e o TCU conferem o RSP. Esta consulta e a versao parametrizada
    dela, com uma linha por chamado.

SAIDA
    UMA linha por SDM. Analitica, para conferencia caso a caso contra as abas
    "Solicitacoes (Encerradas)" e "Incidentes (Encerrados)" do RSP.

--------------------------------------------------------------------------------
POR QUE ESTA CONSULTA FOI REFEITA - o que a evidencia mostrou
--------------------------------------------------------------------------------

    A versao anterior definia "encerrado pelo COI" pelo GRUPO VIGENTE NO MOMENTO
    DO ENCERRAMENTO, reconstruido do historico em dbo.act_log, e aceitava os
    DOIS UUIDs do COI ao mesmo tempo. Ela foi validada contra fevereiro/2026 e
    acertou (493 contra 493 das abas I+R). Essa validacao era INSUFICIENTE: um
    unico periodo nao distingue uma regra correta de uma coincidencia.

    Marco/2026 desfez o empate. Diagnostico executado nos DOIS periodos:

        regra                                          FEV      MAR
        ------------------------------------------  -------  -------
        grupo no encerramento, dois UUIDs (anterior)     493      566
        grupo ATUAL, dois UUIDs somados                  494      648
        grupo ATUAL = COI_Antigo                         494      172
        grupo ATUAL = COI_Novo                             0      476
        ------------------------------------------  -------  -------
        RSP, abas I + R                                  493      471
        RSP, tabela por analista da aba DADOS            492      471

    DOIS achados independentes derrubaram a regra anterior:

    1) O grupo no encerramento PERDE chamados que o RSP conta.
       Dos 471 SDMs listados no RSP de marco, todos os 471 passam em status,
       em tipo I/R e no grupo ATUAL do COI - mas apenas 400 tem o grupo do
       ENCERRAMENTO no COI. Exigir o grupo do encerramento descartaria 71
       chamados reais do relatorio. A reconstrucao por act_log nao e uma
       aproximacao ruim do RSP: e uma pergunta diferente da que o RSP responde.

    2) Somar os dois UUIDs INFLA o resultado.
       Em marco, COI_Novo sozinho da 476 e COI_Antigo sozinho da 172. Juntos,
       648 contra 471 do RSP. O excesso e quase inteiramente o passivo do grupo
       antigo, que continuou encerrando chamados durante marco mas pertence a
       OUTRO contrato - e por isso nao entra no RSP daquele periodo.

    A conclusao das duas: o que decide a populacao de um RSP e o GRUPO ATUAL do
    chamado comparado com O GRUPO QUE ESTA SENDO AUDITADO. Nao e o historico, e
    nao e a uniao dos grupos.

--------------------------------------------------------------------------------
O GRUPO ALVO E CONTEXTO DA APURACAO, NAO UMA FUNCAO DA DATA
--------------------------------------------------------------------------------

    Os dois grupos do COI COEXISTIRAM: o antigo foi sendo descontinuado ao longo
    de marco enquanto o novo entrava em operacao. Os dois estao ATIVOS e com
    membros na base hoje (COI_Novo: 26 membros; COI_Antigo: 35).

    Portanto continua PROIBIDO qualquer corte automatico do tipo
    "antes de marco usa o antigo, depois usa o novo". Um recorte por data
    erraria nos dois sentidos, e a coexistencia e justamente o que o torna
    impossivel de acertar.

    O que substitui isso: quem apura DECLARA qual grupo esta sendo auditado,
    porque essa informacao vem do contrato, nao dos dados. E o parametro
    @COI_GrupoAlvo, logo abaixo. Uma execucao = um grupo.

--------------------------------------------------------------------------------
DIVERGENCIAS RESIDUAIS CONHECIDAS - registradas, NAO contornadas
--------------------------------------------------------------------------------

    fevereiro (grupo antigo) ... consulta 494  x  RSP 493 (abas) / 492 (DADOS)
    marco     (grupo novo) ..... consulta 476  x  RSP 471

    Fevereiro tem +1 sobre as abas: o SDM 1681024. Marco tem +5: os SDMs
    1677562, 1680114, 1682940, 1682966 e 1690023 - todos hoje no COI_Novo, todos
    passando em tipo, status e periodo, e nenhum listado no RSP.

    NENHUM desses seis chamados e excluido por numero. Um CASE que removesse SDM
    especifico para fazer o total fechar destruiria o valor da regra e mentiria
    sobre a qualidade dela.

    A explicacao provavel e a mesma nos dois casos: o RSP e um SNAPSHOT. Ele
    congelou o group_id de cada chamado no instante em que foi gerado; a base
    mostra o group_id de hoje. Chamado que mudou de grupo depois da geracao do
    relatorio aparece aqui e nao la. Isso e uma hipotese com plausibilidade, nao
    um fato provado - e fica registrada como tal.

    Note tambem que o proprio RSP diverge de si mesmo em fevereiro: a tabela por
    analista soma 492 e as abas de detalhe listam 493 SDMs. Sao duas
    apresentacoes da MESMA populacao, com erro de atribuicao nominal de um
    chamado. Nao ha o que escolher entre 492 e 493 - a consulta nao deve ser
    ajustada para nenhum dos dois.

--------------------------------------------------------------------------------
NOTA DE ARQUITETURA - o que saiu, e por que a consulta encolheu tanto
--------------------------------------------------------------------------------

    dbo.act_log NAO E MAIS LIDO. Com ele saiu todo o pipeline de nove passos da
    versao anterior:

        #CandidatosCOI  #AtosCOI  #TransfCOI  #MapaGruposCOI
        #UltimaTransfCOI  #GrupoEncCOI  #FinalCOI  #EventoTermCOI

    Aqueles objetos existiam por UM motivo: reconstruir o grupo vigente no
    encerramento a partir do texto das transferencias. Como esse conceito saiu
    da regra, eles perderam a razao de existir. Nao foram preservados por apego
    a implementacao anterior.

    Consequencias diretas:

      - a maior tabela da base (act_log: ~20,9 milhoes de linhas, ~21 GB) deixou
        de ser tocada;
      - somem o parse de texto, a ponte nome -> UUID e o COLLATE
        Latin1_General_CI_AI que ela obrigava - e com eles some a classe inteira
        de erro que produziu o Msg 451 documentado no historico;
      - somem as colunas [Grupo no Encerramento], [UUID Grupo no Encerramento],
        [Fonte Grupo no Encerramento], [Evento Terminal] e [Analista do Evento
        Terminal], que so faziam sentido enquanto a regra dependia do historico.

    O historico do act_log nao foi desqualificado como fonte - ele responde uma
    pergunta legitima ("onde o chamado estava quando fechou?"). Apenas nao e a
    pergunta que o RSP responde.

Somente leitura. Sem GO. Uma execucao = um grupo, um periodo.
================================================================================
*/

--------------------------------------------------------------------------------
-- [0] PARAMETROS
--------------------------------------------------------------------------------

-- Periodo em horario do Brasil, intervalo SEMIABERTO: >= inicio e < fim.
-- O fim e o PRIMEIRO INSTANTE DE FORA. Nunca usar 23:59:59: o chamado fechado
-- no ultimo segundo do dia ficaria de fora.
-- [POWER BI] Periodo automatico, calculado no inicio do arquivo.
DECLARE @DataInicio datetime2(0) = @PBI_InicioBR;   -- inclusivo
DECLARE @DataFim    datetime2(0) = @PBI_FimBR;      -- EXCLUSIVO

-- Identidade do COI. SEMPRE por UUID: nome de grupo muda, UUID nao.
DECLARE @COI_Antigo varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;  -- 'Contrato 7/2023 - COI'
DECLARE @COI_Novo   varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;  -- 'COI'

--------------------------------------------------------------------------------
-- GRUPO ALVO DA APURACAO - a unica linha que decide QUAL contrato esta sendo
-- auditado. Trocar aqui, a mao, junto com o periodo.
--
--     producao / contrato vigente ............... @COI_Novo
--     conferencia do RSP de fevereiro/2026 ...... @COI_Antigo
--
-- NAO combinar os dois. Somar COI_Antigo + COI_Novo em marco/2026 leva o
-- resultado de 476 para 648, contra 471 do RSP: a uniao junta dois contratos
-- diferentes na mesma apuracao.
--
-- NAO escolher automaticamente pela data. Os dois grupos coexistiram durante a
-- transicao; qualquer corte por periodo erra nos dois sentidos.
--
-- O par (periodo, grupo) vem do contrato que esta sendo conferido, e por isso e
-- declarado por quem apura - nao inferido dos dados.
--------------------------------------------------------------------------------
DECLARE @COI_GrupoAlvo varbinary(16) = @COI_Novo;

-- 0 = apenas o resultado analitico (uso normal do relatorio).
-- 1 = acrescenta um result set de conferencia: estado do grupo alvo,
--     COUNT(*) x COUNT(DISTINCT SDM) e a quebra por tipo e status.
DECLARE @MostrarDiagnostico bit = 0;

-- Conversao para o epoch inteiro em que call_req guarda as datas.
-- Feita UMA vez, em variavel: nenhuma funcao encosta na coluna filtrada, entao
-- close_date continua sargavel.
DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';
DECLARE @IniEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @DataInicio));
DECLARE @FimEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @DataFim));

--------------------------------------------------------------------------------
-- [1] VALIDACAO DO GRUPO ALVO
--
-- E o CTE "Fornecedores" da Consulta para Auditoria, que exige que o grupo
-- esteja ATIVO (ca_contact.inactive = 0) e tenha ao menos UM membro em grpmem.
--
-- La isso e um INNER JOIN em grpmem, que multiplicaria o chamado por membro do
-- grupo se nao houvesse um ROW_NUMBER de desempate. Aqui a checagem e feita UMA
-- vez, sobre o parametro, e nao por linha: grpmem nunca entra no FROM da
-- populacao, entao nao existe caminho para duplicar chamado.
--
-- Os dois grupos passam nos dois testes hoje (COI_Novo: inactive 0, 26 membros;
-- COI_Antigo: inactive 0, 35 membros), portanto este bloco nao altera nenhum
-- dos totais medidos. Ele existe para preservar a equivalencia literal com a
-- Auditoria e para que um grupo desativado no futuro nao passe despercebido.
--
-- O PRINT e o antidoto para o zero silencioso: sem ele, um grupo inativo
-- devolveria uma lista vazia que se parece com "nao houve encerramento no
-- periodo". Com ele, a razao aparece na aba de mensagens.
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

PRINT N'Grupo alvo ... ' + CONVERT(nvarchar(50), @COI_GrupoAlvo, 1)
    + N'  nome: ' + ISNULL(@GrupoNome, N'NAO ENCONTRADO em ca_contact')
    + N'  inactive: ' + ISNULL(CONVERT(nvarchar(10), @GrupoInativo), N'-')
    + N'  membros: ' + CONVERT(nvarchar(20), ISNULL(@GrupoMembros, 0));
PRINT N'Periodo ...... >= ' + CONVERT(nvarchar(19), @DataInicio, 120)
    + N'  e  < ' + CONVERT(nvarchar(19), @DataFim, 120);

IF @GrupoAlvoValido = 0
    PRINT N'ATENCAO: o grupo alvo NAO passa no filtro da Consulta para Auditoria '
        + N'(precisa existir, estar com inactive = 0 e ter ao menos um membro em grpmem). '
        + N'O resultado sera VAZIO por causa disso, e nao por ausencia de encerramentos.';

--------------------------------------------------------------------------------
-- [2] POPULACAO - a regra inteira mora neste unico WHERE.
--
-- SARGABILIDADE: as quatro colunas filtradas - close_date, status, type e
-- group_id - aparecem CRUAS, sem funcao, CAST ou COLLATE. As conversoes de data
-- ja foram resolvidas em variavel no passo [0].
--
-- Todos os LEFT JOIN sao contra chave UNICA do lado direito (contact_uuid,
-- cr_stat.code, prob_ctg.persid, ca_owned_resource.own_resource_uuid), portanto
-- nenhum deles pode multiplicar linha. Ver a nota de duplicidade no passo [3].
--
-- OPTION (RECOMPILE): @IniEpoch, @FimEpoch e @COI_GrupoAlvo sao variaveis
-- locais, e sem RECOMPILE o otimizador nao enxerga o valor delas - cai num
-- chute generico de seletividade. group_id = <um grupo> e muito seletivo; com o
-- valor real na mao o plano escolhido e outro.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#EncerradosCOI') IS NOT NULL DROP TABLE #EncerradosCOI;

SELECT
    r.ref_num AS [SDM],

    CASE r.[type]
        WHEN 'I' THEN N'Incidente'
        WHEN 'R' THEN N'Solicitação'
        ELSE CONCAT(N'Outro/Não mapeado: ', ISNULL(CONVERT(nvarchar(10), r.[type]), N'NULO'))
    END AS [Tipo Chamado],

    ISNULL(pc.sym, N'N/A') AS [Símbolo],

    LTRIM(RTRIM(ISNULL(r.summary, N''))) AS [Resumo],

    ISNULL(ci.resource_name, N'N/A') AS [Item de Configuração],

    CASE r.priority
        WHEN 1 THEN N'1 - Máxima'
        WHEN 2 THEN N'2 - Alta'
        WHEN 3 THEN N'3 - Média'
        WHEN 4 THEN N'4 - Baixa'
        WHEN 5 THEN N'5 - Mínima'
        ELSE N'N/A'
    END AS [Prioridade],

    ISNULL(st.sym, N'N/A') AS [Status],
    r.status AS [Código Status],

    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date,  @Epoch)) AS [Data de Abertura],
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.close_date, @Epoch)) AS [Data de Encerramento],
    CASE WHEN r.resolve_date IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.resolve_date, @Epoch))
    END AS [Data de Resolução],

    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(resp.first_name, N'') <> N'' OR ISNULL(resp.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(resp.first_name, N''), N' ', ISNULL(resp.last_name, N''))
            WHEN ISNULL(resp.userid, N'') <> N'' THEN resp.userid
            ELSE N'N/A'
        END
    )) AS [Responsável],

    LTRIM(RTRIM(COALESCE(NULLIF(grp.last_name, N''), NULLIF(grp.userid, N''), N'N/A'))) AS [Grupo Atual],
    r.group_id AS [UUID Grupo Atual]

INTO #EncerradosCOI

FROM dbo.call_req AS r
LEFT JOIN dbo.cr_stat AS st
    ON st.code = r.status
LEFT JOIN dbo.ca_contact AS resp
    ON resp.contact_uuid = r.assignee
LEFT JOIN dbo.ca_contact AS grp
    ON grp.contact_uuid = r.group_id
LEFT JOIN dbo.prob_ctg AS pc
    ON pc.persid = r.category
LEFT JOIN dbo.ca_owned_resource AS ci
    ON ci.own_resource_uuid = r.affected_rc

WHERE r.close_date >= @IniEpoch
  AND r.close_date <  @FimEpoch
  AND r.[type]   IN ('I', 'R')
  AND r.status   IN ('CL', 'CLUNRSLV')
  AND r.group_id = @COI_GrupoAlvo
  AND @GrupoAlvoValido = 1
OPTION (RECOMPILE);

--------------------------------------------------------------------------------
-- [3] RESULTADO - uma linha por SDM.
--
-- DUPLICIDADE, e por que ela e impossivel aqui:
--
--   a) a populacao sai de UMA passagem em dbo.call_req, sem EXISTS que se
--      transforme em join, sem UNION e sem subconsulta correlacionada. Uma
--      linha de call_req = um chamado;
--   b) os cinco LEFT JOIN sao todos contra chave UNICA do lado direito, entao
--      nenhum deles acrescenta linha;
--   c) grpmem, que era o unico caminho real para multiplicacao (um chamado por
--      membro do grupo), NAO participa da populacao - foi resolvido como
--      checagem escalar sobre o parametro no passo [1].
--
--   A garantia e estrutural, nao vem de DISTINCT. Com @MostrarDiagnostico = 1 o
--   result set de conferencia mostra COUNT(*) e COUNT(DISTINCT SDM) lado a
--   lado; se algum dia divergirem, a causa e (a) ou (b), nunca grpmem.
--
-- O indice e NAO UNICO de proposito: se a regra passar a duplicar SDM, isso
-- deve aparecer na conferencia, e nao como falha bruta de criacao de indice que
-- esconde o diagnostico.
--------------------------------------------------------------------------------
CREATE CLUSTERED INDEX IX_EncerradosCOI ON #EncerradosCOI([SDM]);

SELECT
    [SDM],
    [Tipo Chamado],
    [Símbolo],
    [Resumo],
    [Item de Configuração],
    [Prioridade],
    [Status],
    [Código Status],
    [Data de Abertura],
    [Data de Encerramento],
    [Data de Resolução],
    [Responsável],
    [Grupo Atual],
    [UUID Grupo Atual]
FROM #EncerradosCOI
ORDER BY [Data de Encerramento] ASC, [SDM] ASC;

--------------------------------------------------------------------------------
-- [4] CONFERENCIA - opcional, fora do resultado oficial.
--
-- Le a temp table que o passo [2] deixou na sessao. A regra NAO e reescrita
-- aqui: se fosse, as duas copias poderiam divergir e a conferencia passaria a
-- confirmar a si mesma.
--------------------------------------------------------------------------------
IF @MostrarDiagnostico = 1
BEGIN
    SELECT
        N'grupo alvo' AS [bloco],
        @COI_GrupoAlvo AS [UUID],
        CASE WHEN @COI_GrupoAlvo = @COI_Antigo THEN N'COI_Antigo'
             WHEN @COI_GrupoAlvo = @COI_Novo   THEN N'COI_Novo'
             ELSE N'FORA dos dois UUIDs oficiais do COI' END AS [qual],
        @GrupoNome    AS [nome em ca_contact],
        @GrupoInativo AS [inactive],
        @GrupoMembros AS [membros em grpmem],
        @DataInicio   AS [periodo >=],
        @DataFim      AS [periodo <],
        COUNT_BIG(*)                        AS [linhas],
        COUNT_BIG(DISTINCT e.[SDM])         AS [SDMs distintos],
        COUNT_BIG(*) - COUNT_BIG(DISTINCT e.[SDM]) AS [duplicidade],
        SUM(CASE WHEN e.[Tipo Chamado] = N'Incidente'   THEN 1 ELSE 0 END) AS [Incidentes],
        SUM(CASE WHEN e.[Tipo Chamado] = N'Solicitação' THEN 1 ELSE 0 END) AS [Solicitações],
        SUM(CASE WHEN e.[Código Status] = 'CL'       THEN 1 ELSE 0 END) AS [CL],
        SUM(CASE WHEN e.[Código Status] = 'CLUNRSLV' THEN 1 ELSE 0 END) AS [CLUNRSLV]
    FROM #EncerradosCOI AS e;
END;
