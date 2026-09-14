USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- GRÁFICO 2 - BO
-- Chamados Encerrados vs Registrados (diário) - ESCOPO: apenas COI antigo.
--
-- "Registrados": filtro direto por group_id + open_date (igual ao antigo
--    #Abertos da consulta gráfico_2, só que restrito a um único grupo).
-- "Encerrados":  filtro direto por group_id + close_date (igual ao antigo
--    #Encerrados da consulta gráfico_2).
--
-- Sem motor de log/evidência de transferência. Simetria total entre
-- Registrados e Encerrados: a única diferença entre os dois blocos é qual
-- data filtra (open_date vs close_date).
--
-- "Resultado Geral": UNIÃO (sem duplicar) dos chamados que aparecem em
--    Registrados OU em Encerrados dentro do período.
--
-- Escopo de grupo: SOMENTE 0xDA7095D797E3FE498A62B79CB7EAED15 ("COI antigo"),
-- por pedido do gerente. O UUID "COI_Novo" NÃO entra nesta consulta.
--
-- Consulta 100% de LEITURA. As únicas "escritas" são em tabelas temporárias
-- de sessão (#...), usadas só para organizar o SELECT. Nenhuma tabela do
-- banco é alterada (sem INSERT/UPDATE/DELETE em tabela real).
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- [CONFIGURACAO DAS JANELAS DE RESULTADO]
-- 1 = retorna a janela; 0 = nao retorna.
--------------------------------------------------------------------------------
DECLARE @ResultadoGeral bit = 1; -- Todos os chamados (Registrados UNION Encerrados)
DECLARE @Registrados    bit = 0; -- Só os chamados Registrados no período
DECLARE @Encerrados     bit = 0; -- Só os chamados Encerrados no período
DECLARE @Diario         bit = 0; -- Dia | Registrados | Encerrados

--------------------------------------------------------------------------------
-- [PARAMETROS GERAIS]
--------------------------------------------------------------------------------
DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';

-- Período analisado (aplicado a Registrados E Encerrados). Ajuste aqui.
DECLARE @InicioBR datetime2(0) = '2025-10-01 00:00:00';
DECLARE @FimBR    datetime2(0) = '2025-10-31 23:59:59';

DECLARE @InicioEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @InicioBR));
DECLARE @FimEpoch    int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @FimBR));

-- Somente o COI antigo, conforme pedido do gerente.
DECLARE @COI varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;

--------------------------------------------------------------------------------
-- [BASE REGISTRADOS] Chamados com open_date no período, group_id = COI antigo
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Registrados') IS NOT NULL DROP TABLE #Registrados;

SELECT
    r.id,
    r.ref_num,
    r.[type]      AS tipo,
    r.priority,
    r.status,
    r.category,
    r.assignee,
    r.log_agent,
    r.summary     AS resumo,
    r.open_date,
    r.close_date,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date, @Epoch)) AS abertura_br
INTO #Registrados
FROM dbo.call_req AS r
WHERE r.group_id = @COI
  AND r.[type] IN ('I', 'R')
  AND r.open_date IS NOT NULL
  AND r.open_date >= @InicioEpoch
  AND r.open_date <= @FimEpoch;

CREATE INDEX IX_Registrados_open ON #Registrados(open_date);

--------------------------------------------------------------------------------
-- [BASE ENCERRADOS] Chamados com close_date no período, group_id = COI antigo
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Encerrados') IS NOT NULL DROP TABLE #Encerrados;

SELECT
    r.id,
    r.ref_num,
    r.[type]      AS tipo,
    r.priority,
    r.status,
    r.category,
    r.assignee,
    r.log_agent,
    r.summary     AS resumo,
    r.open_date,
    r.close_date,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date,  @Epoch)) AS abertura_br,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.close_date, @Epoch)) AS encerramento_br
INTO #Encerrados
FROM dbo.call_req AS r
WHERE r.group_id = @COI
  AND r.[type] IN ('I', 'R')
  AND r.close_date IS NOT NULL
  AND r.close_date >= @InicioEpoch
  AND r.close_date <= @FimEpoch;

CREATE INDEX IX_Encerrados_close ON #Encerrados(close_date);

--------------------------------------------------------------------------------
-- [ENRIQUECIMENTO] Mesmas colunas de negócio para os dois lados, via os
-- mesmos JOINs (cr_stat/prob_ctg/pri/ca_contact).
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#RegistradosSaida') IS NOT NULL DROP TABLE #RegistradosSaida;

SELECT
    N'COI'                                                AS [Nucleo],
    x.ref_num                                             AS [SDM],
    CASE x.tipo
        WHEN 'I' THEN N'Incidente'
        WHEN 'R' THEN N'Solicitação'
        ELSE CONCAT(N'Outro/Não mapeado: ', ISNULL(CONVERT(nvarchar(10), x.tipo), N'NULO'))
    END                                                    AS [Tipo do Chamado],
    CASE
        WHEN TRY_CONVERT(tinyint, pri.sym) BETWEEN 1 AND 5 THEN
            CASE TRY_CONVERT(tinyint, pri.sym)
                WHEN 1 THEN N'1 - Máxima' WHEN 2 THEN N'2 - Alta' WHEN 3 THEN N'3 - Média'
                WHEN 4 THEN N'4 - Baixa' WHEN 5 THEN N'5 - Mínima' END
        WHEN x.priority BETWEEN 1 AND 5 THEN
            CASE CONVERT(tinyint, x.priority)
                WHEN 1 THEN N'1 - Máxima' WHEN 2 THEN N'2 - Alta' WHEN 3 THEN N'3 - Média'
                WHEN 4 THEN N'4 - Baixa' WHEN 5 THEN N'5 - Mínima' END
        ELSE N'NãoInformada'
    END                                                    AS [Severidade],
    ISNULL(st.sym, N'N/A')                                 AS [Status],
    ISNULL(pc.sym, N'N/A')                                 AS [Categoria],
    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(la.first_name, N'') <> N'' OR ISNULL(la.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(la.first_name, N''), N' ', ISNULL(la.last_name, N''))
            WHEN ISNULL(la.userid, N'') <> N'' THEN la.userid
            ELSE N'N/A'
        END
    ))                                                     AS [Responsável Abertura],
    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(asg.first_name, N'') <> N'' OR ISNULL(asg.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(asg.first_name, N''), N' ', ISNULL(asg.last_name, N''))
            WHEN ISNULL(asg.userid, N'') <> N'' THEN asg.userid
            ELSE N'N/A'
        END
    ))                                                     AS [Responsável Atendimento],
    LTRIM(RTRIM(CONVERT(nvarchar(4000), x.resumo)))        AS [Resumo],
    x.abertura_br                                          AS [Data de Abertura],
    x.id                                                   AS id_chamado
INTO #RegistradosSaida
FROM #Registrados AS x
LEFT JOIN dbo.cr_stat AS st
    ON st.code = x.status
LEFT JOIN dbo.prob_ctg AS pc
    ON pc.persid = x.category
LEFT JOIN dbo.pri AS pri
    ON pri.enum = x.priority
LEFT JOIN dbo.ca_contact AS la
    ON la.contact_uuid = x.log_agent
LEFT JOIN dbo.ca_contact AS asg
    ON asg.contact_uuid = x.assignee;

CREATE INDEX IX_RegistradosSaida_id ON #RegistradosSaida(id_chamado);

IF OBJECT_ID('tempdb..#EncerradosSaida') IS NOT NULL DROP TABLE #EncerradosSaida;

SELECT
    N'COI'                                                AS [Nucleo],
    x.ref_num                                             AS [SDM],
    CASE x.tipo
        WHEN 'I' THEN N'Incidente'
        WHEN 'R' THEN N'Solicitação'
        ELSE CONCAT(N'Outro/Não mapeado: ', ISNULL(CONVERT(nvarchar(10), x.tipo), N'NULO'))
    END                                                    AS [Tipo do Chamado],
    CASE
        WHEN TRY_CONVERT(tinyint, pri.sym) BETWEEN 1 AND 5 THEN
            CASE TRY_CONVERT(tinyint, pri.sym)
                WHEN 1 THEN N'1 - Máxima' WHEN 2 THEN N'2 - Alta' WHEN 3 THEN N'3 - Média'
                WHEN 4 THEN N'4 - Baixa' WHEN 5 THEN N'5 - Mínima' END
        WHEN x.priority BETWEEN 1 AND 5 THEN
            CASE CONVERT(tinyint, x.priority)
                WHEN 1 THEN N'1 - Máxima' WHEN 2 THEN N'2 - Alta' WHEN 3 THEN N'3 - Média'
                WHEN 4 THEN N'4 - Baixa' WHEN 5 THEN N'5 - Mínima' END
        ELSE N'NãoInformada'
    END                                                    AS [Severidade],
    ISNULL(st.sym, N'N/A')                                 AS [Status],
    ISNULL(pc.sym, N'N/A')                                 AS [Categoria],
    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(la.first_name, N'') <> N'' OR ISNULL(la.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(la.first_name, N''), N' ', ISNULL(la.last_name, N''))
            WHEN ISNULL(la.userid, N'') <> N'' THEN la.userid
            ELSE N'N/A'
        END
    ))                                                     AS [Responsável Abertura],
    LTRIM(RTRIM(
        CASE
            WHEN (ISNULL(asg.first_name, N'') <> N'' OR ISNULL(asg.last_name, N'') <> N'')
                THEN CONCAT(ISNULL(asg.first_name, N''), N' ', ISNULL(asg.last_name, N''))
            WHEN ISNULL(asg.userid, N'') <> N'' THEN asg.userid
            ELSE N'N/A'
        END
    ))                                                     AS [Responsável Atendimento],
    LTRIM(RTRIM(CONVERT(nvarchar(4000), x.resumo)))        AS [Resumo],
    x.abertura_br                                          AS [Data de Abertura],
    x.id                                                   AS id_chamado
INTO #EncerradosSaida
FROM #Encerrados AS x
LEFT JOIN dbo.cr_stat AS st
    ON st.code = x.status
LEFT JOIN dbo.prob_ctg AS pc
    ON pc.persid = x.category
LEFT JOIN dbo.pri AS pri
    ON pri.enum = x.priority
LEFT JOIN dbo.ca_contact AS la
    ON la.contact_uuid = x.log_agent
LEFT JOIN dbo.ca_contact AS asg
    ON asg.contact_uuid = x.assignee;

CREATE INDEX IX_EncerradosSaida_id ON #EncerradosSaida(id_chamado);

--------------------------------------------------------------------------------
-- [SAIDA RESULTADO GERAL] União (sem duplicar) de Registrados + Encerrados.
-- Um chamado que é Registrado E Encerrado no período aparece só 1 vez aqui.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#ResultadoGeral') IS NOT NULL DROP TABLE #ResultadoGeral;

SELECT
    [Nucleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
    [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura],
    id_chamado
INTO #ResultadoGeral
FROM (
    SELECT [Nucleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
           [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura], id_chamado
    FROM #RegistradosSaida
    UNION
    SELECT [Nucleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
           [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura], id_chamado
    FROM #EncerradosSaida
) AS u;

--------------------------------------------------------------------------------
-- [JANELAS DE RESULTADO]
-- Cada janela ativa retorna a lista de chamados + um segundo result set com
-- a "Qtde de Chamados" daquela janela.
--------------------------------------------------------------------------------
IF @ResultadoGeral = 1
BEGIN
    SELECT
        [Nucleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #ResultadoGeral
    ORDER BY [Data de Abertura];

    SELECT N'Resultado Geral' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #ResultadoGeral;
END;

IF @Registrados = 1
BEGIN
    SELECT
        [Nucleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #RegistradosSaida
    ORDER BY [Data de Abertura];

    SELECT N'Registrados' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #RegistradosSaida;
END;

IF @Encerrados = 1
BEGIN
    SELECT
        [Nucleo], [SDM], [Tipo do Chamado], [Severidade], [Status], [Categoria],
        [Responsável Abertura], [Responsável Atendimento], [Resumo], [Data de Abertura]
    FROM #EncerradosSaida
    ORDER BY [Data de Abertura];

    SELECT N'Encerrados' AS [Janela], COUNT(*) AS [Qtde de Chamados]
    FROM #EncerradosSaida;
END;

IF @Diario = 1
BEGIN
    IF OBJECT_ID('tempdb..#Diario') IS NOT NULL DROP TABLE #Diario;

    ;WITH DiasMovimento AS (
        SELECT CAST(r.abertura_br      AS date) AS dia FROM #Registrados AS r
        UNION
        SELECT CAST(e.encerramento_br  AS date) AS dia FROM #Encerrados  AS e
    )
    SELECT
        dm.dia                          AS Dia,
        ISNULL(reg.QtdRegistrados, 0)   AS Registrados,
        ISNULL(enc.QtdEncerrados,  0)   AS Encerrados
    INTO #Diario
    FROM DiasMovimento AS dm
    LEFT JOIN (
        SELECT CAST(r.abertura_br AS date) AS dia, COUNT(*) AS QtdRegistrados
        FROM #Registrados AS r
        GROUP BY CAST(r.abertura_br AS date)
    ) AS reg ON reg.dia = dm.dia
    LEFT JOIN (
        SELECT CAST(e.encerramento_br AS date) AS dia, COUNT(*) AS QtdEncerrados
        FROM #Encerrados AS e
        GROUP BY CAST(e.encerramento_br AS date)
    ) AS enc ON enc.dia = dm.dia;

    SELECT Dia, Registrados, Encerrados
    FROM #Diario
    ORDER BY Dia;

    SELECT
        N'Diário'                          AS [Janela],
        SUM(Registrados)                   AS [Qtde de Chamados Registrados],
        SUM(Encerrados)                    AS [Qtde de Chamados Encerrados],
        SUM(Registrados) + SUM(Encerrados) AS [Qtde de Chamados]
    FROM #Diario;
END;