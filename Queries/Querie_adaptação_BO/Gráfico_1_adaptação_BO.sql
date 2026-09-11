USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- GRÁFICO 1 - TESTE BO
-- Consulta de VALIDAÇÃO: retorna os chamados CRUS (uma linha por chamado),
-- sem nenhuma agregação mensal, sem cálculo de POP/anexo e sem motor de
-- SLA/FAIA/FARC. O objetivo é apenas listar os chamados para conferência
-- manual contra a planilha "Análise de chamados" e contra os números do
-- Gráfico 1.
--
-- Esta consulta é 100% de LEITURA. As únicas "escritas" são em tabela
-- temporária de sessão (#Base) e em variável de tabela (@Grupos), usadas só
-- para organizar o SELECT; nenhuma tabela do banco é alterada
-- (sem INSERT/UPDATE/DELETE em tabela real).
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- [PARAMETROS]
--------------------------------------------------------------------------------
DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch              datetime2(0) = '1970-01-01 00:00:00';

-- Período de análise em horário do Brasil (ajuste aqui conforme necessário).
-- Default abaixo: outubro e novembro/2025, os meses usados na conferência manual.
DECLARE @InicioBR datetime2(0) = '2025-10-01 00:00:00';
DECLARE @FimBR    datetime2(0) = '2025-10-30 23:59:59';

DECLARE @InicioUTC datetime2(0) = DATEADD(HOUR, @HorasBrasilParaUTC, @InicioBR);
DECLARE @FimUTC    datetime2(0) = DATEADD(HOUR, @HorasBrasilParaUTC, @FimBR);

DECLARE @InicioEpoch int = DATEDIFF(SECOND, @Epoch, @InicioUTC);
DECLARE @FimEpoch    int = DATEDIFF(SECOND, @Epoch, @FimUTC);

--------------------------------------------------------------------------------
-- [CODIGOS DOS NUCLEOS] Contrato 7/2023
--
-- ATENCAO / PONTO PARA VOCE VALIDAR:
-- O grupo COI abaixo (0xDA70...) corresponde ao que a consulta gráfico_1
-- chamava de "COI_Antigo". Aquela consulta somava TAMBEM um segundo grupo,
-- "COI_Novo" (0x3C11B3A9EBCE5D498E2F7D7FF385F967), que NAO esta na lista de
-- codigos que voce passou para esta consulta. Se o COI tiver chamados
-- tambem nesse segundo grupo dentro do periodo, a janela @COI aqui pode
-- ficar MENOR que o total do Grafico 1. Me avise se quiser que eu inclua
-- os dois codigos do COI na janela @COI (e no Resultado Geral).
--------------------------------------------------------------------------------
DECLARE @COI_ID                varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;
DECLARE @NSTI_AD_WORKPLACE_ID  varbinary(16) = 0x7407C52C39642942A0E43CFF4287BB17;
DECLARE @NSTI_APLICACAO_ID     varbinary(16) = 0x02990B31D745314FB9258FA50A4FCE31;
DECLARE @NSTI_BD_ID            varbinary(16) = 0xF9439CC8EE970E47B9BB33EA6490A144;
DECLARE @NSTI_BI_ANALYTICS_ID  varbinary(16) = 0xE6BC79076E12BB478F2C0CD4F35EF1B5;
DECLARE @NSTI_GCM_ID           varbinary(16) = 0x889CEE67FA9FE746BF8ECDD8A3040F65;
DECLARE @NSTI_PLAN_PROC_DOC_ID varbinary(16) = 0xF458F2D07FF9F9479928BB3EB8154DD9;
DECLARE @NSTI_REDE_ID          varbinary(16) = 0xAD88846F0861A64F8620B2AD5B94B71F;
DECLARE @NSTI_SEGURANCA_ID     varbinary(16) = 0x01E86513E46D85448B33919F8802E2EB;
DECLARE @NSTI_SO_ID            varbinary(16) = 0xF46720F63EAE3946B08ADDBCC732132F;

DECLARE @Grupos TABLE (
    group_id varbinary(16) NOT NULL PRIMARY KEY,
    Nucleo   nvarchar(100) NOT NULL
);
INSERT INTO @Grupos (group_id, Nucleo) VALUES
    (@COI_ID,                N'COI'),
    (@NSTI_AD_WORKPLACE_ID,  N'NSTI AD-WORKPLACE'),
    (@NSTI_APLICACAO_ID,     N'NSTI APLICAÇÃO'),
    (@NSTI_BD_ID,            N'NSTI BD'),
    (@NSTI_BI_ANALYTICS_ID,  N'NSTI BI-ANALYTICS'),
    (@NSTI_GCM_ID,           N'NSTI GCM'),
    (@NSTI_PLAN_PROC_DOC_ID, N'NSTI PLAN-PROC-DOC'),
    (@NSTI_REDE_ID,          N'NSTI REDE'),
    (@NSTI_SEGURANCA_ID,     N'NSTI SEGURANÇA'),
    (@NSTI_SO_ID,            N'NSTI SO');

--------------------------------------------------------------------------------
-- [CONFIGURACAO DAS JANELAS DE RESULTADO]
-- 1 = retorna a janela; 0 = nao retorna.
--------------------------------------------------------------------------------
DECLARE @ResultadoGeral     bit = 1;

DECLARE @COI                bit = 0;
DECLARE @NSTI_AD_WORKPLACE  bit = 0;
DECLARE @NSTI_APLICACAO     bit = 0;
DECLARE @NSTI_BD            bit = 0;
DECLARE @NSTI_BI_ANALYTICS  bit = 0;
DECLARE @NSTI_GCM           bit = 0;
DECLARE @NSTI_PLAN_PROC_DOC bit = 0;
DECLARE @NSTI_REDE          bit = 0;
DECLARE @NSTI_SEGURANCA     bit = 0;
DECLARE @NSTI_SO            bit = 0;

--------------------------------------------------------------------------------
-- [BASE] Chamados com open_date no período, nos núcleos do Contrato 7/2023
-- Sem filtro de tipo (I/R/P/C...) e sem filtro de status: a ideia é ver tudo
-- que existe, com a coluna "Tipo do Chamado" mostrando o que apareceu.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Base') IS NOT NULL DROP TABLE #Base;

SELECT
    g.Nucleo                                            AS [Núcleo],
    r.ref_num                                           AS [SDM],

    CASE r.[type]
        WHEN 'I' THEN N'Incidente'
        WHEN 'R' THEN N'Solicitação'
        WHEN 'P' THEN N'Problema'
        WHEN 'C' THEN N'Mudança'
        ELSE CONCAT(N'Outro/Não mapeado: ', ISNULL(CONVERT(nvarchar(10), r.[type]), N'NULO'))
    END                                                  AS [Tipo do Chamado],

    CASE
        WHEN TRY_CONVERT(tinyint, pri.sym) BETWEEN 1 AND 5 THEN
            CASE TRY_CONVERT(tinyint, pri.sym)
                WHEN 1 THEN N'1 - Máxima'
                WHEN 2 THEN N'2 - Alta'
                WHEN 3 THEN N'3 - Média'
                WHEN 4 THEN N'4 - Baixa'
                WHEN 5 THEN N'5 - Mínima'
            END
        WHEN r.priority BETWEEN 1 AND 5 THEN
            CASE CONVERT(tinyint, r.priority)
                WHEN 1 THEN N'1 - Máxima'
                WHEN 2 THEN N'2 - Alta'
                WHEN 3 THEN N'3 - Média'
                WHEN 4 THEN N'4 - Baixa'
                WHEN 5 THEN N'5 - Mínima'
            END
        ELSE N'NãoInformada'
    END                                                  AS [Severidade],

    ISNULL(st.sym, N'N/A')                               AS [Status],
    ISNULL(pc.sym, N'N/A')                               AS [Categoria],

    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(la.first_name, N'') <> N'' OR ISNULL(la.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(la.first_name, N''), N' ', ISNULL(la.last_name, N''))
            WHEN ISNULL(la.userid, N'') <> N'' THEN la.userid
            ELSE N'N/A'
        END
    ))                                                   AS [Responsável Abertura],

    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(asg.first_name, N'') <> N'' OR ISNULL(asg.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(asg.first_name, N''), N' ', ISNULL(asg.last_name, N''))
            WHEN ISNULL(asg.userid, N'') <> N'' THEN asg.userid
            ELSE N'N/A'
        END
    ))                                                   AS [Responsável Atendimento],

    LTRIM(RTRIM(CONVERT(nvarchar(4000), r.summary)))     AS [Resumo],

    CASE WHEN r.open_date IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date, @Epoch))
    END                                                  AS [Data de Abertura],

    r.group_id
INTO #Base
FROM dbo.call_req AS r
JOIN @Grupos AS g
    ON g.group_id = r.group_id
LEFT JOIN dbo.cr_stat AS st
    ON st.code = r.status
LEFT JOIN dbo.prob_ctg AS pc
    ON pc.persid = r.category
LEFT JOIN dbo.pri AS pri
    ON pri.enum = r.priority
LEFT JOIN dbo.ca_contact AS la
    ON la.contact_uuid = r.log_agent
LEFT JOIN dbo.ca_contact AS asg
    ON asg.contact_uuid = r.assignee
WHERE r.open_date IS NOT NULL
  AND r.open_date >= @InicioEpoch
  AND r.open_date <= @FimEpoch;

CREATE INDEX IX_Base_group ON #Base(group_id);

--------------------------------------------------------------------------------
-- [JANELAS DE RESULTADO]
-- Cada janela ativa retorna a lista de chamados + um segundo result set com
-- a "Qtde de Chamados" daquela janela.
--------------------------------------------------------------------------------
IF @ResultadoGeral = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    ORDER BY [Núcleo], [Data de Abertura];

    SELECT N'Resultado Geral' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base;
END;

IF @COI = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @COI_ID
    ORDER BY [Data de Abertura];

    SELECT N'COI' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @COI_ID;
END;

IF @NSTI_AD_WORKPLACE = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_AD_WORKPLACE_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI AD-WORKPLACE' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_AD_WORKPLACE_ID;
END;

IF @NSTI_APLICACAO = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_APLICACAO_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI APLICAÇÃO' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_APLICACAO_ID;
END;

IF @NSTI_BD = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_BD_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI BD' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_BD_ID;
END;

IF @NSTI_BI_ANALYTICS = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_BI_ANALYTICS_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI BI-ANALYTICS' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_BI_ANALYTICS_ID;
END;

IF @NSTI_GCM = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_GCM_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI GCM' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_GCM_ID;
END;

IF @NSTI_PLAN_PROC_DOC = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_PLAN_PROC_DOC_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI PLAN-PROC-DOC' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_PLAN_PROC_DOC_ID;
END;

IF @NSTI_REDE = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_REDE_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI REDE' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_REDE_ID;
END;

IF @NSTI_SEGURANCA = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_SEGURANCA_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI SEGURANÇA' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_SEGURANCA_ID;
END;

IF @NSTI_SO = 1
BEGIN
    SELECT
        [Núcleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #Base
    WHERE group_id = @NSTI_SO_ID
    ORDER BY [Data de Abertura];

    SELECT N'NSTI SO' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #Base
    WHERE group_id = @NSTI_SO_ID;
END;