USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- [CONFIGURACAO DAS JANELAS DE RESULTADO]
-- 1 = retorna a janela; 0 = nao retorna.
--------------------------------------------------------------------------------
DECLARE @ResultadoTudo   bit = 1;

DECLARE @G1_Mensal       bit = 1; -- Janela do Gráfico 1: Mensal (Volumetria)
DECLARE @Detalhes        bit = 1; -- Janela de Auditoria: Detalhe linha a linha

--------------------------------------------------------------------------------
-- [0] PARAMETROS GERAIS UNIFICADOS
--------------------------------------------------------------------------------
DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';

-- Período analisado (Aplicado para TODAS as janelas)
DECLARE @InicioBR datetime2(0) = '2026-03-09 00:00:00';   -- INCLUSIVO
DECLARE @FimBR    datetime2(0) = '2026-03-31 23:59:59';   -- EXCLUSIVO

DECLARE @InicioEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @InicioBR));
DECLARE @FimEpoch    int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @FimBR));

-- Identidade do COI por UUID (Para fallback quando não há histórico de logs 'TR')
DECLARE @COI_Antigo varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;  -- 'Contrato 7/2023 - COI'
DECLARE @COI_Novo   varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;  -- 'COI'

DECLARE @HorizonteMensal bit = 1;

--------------------------------------------------------------------------------
-- MOTOR CENTRAL: REGRA CANONICA DE REGISTRADOS COI
--------------------------------------------------------------------------------

-- [R1] Aliases históricos confirmados da fila
IF OBJECT_ID('tempdb..#AliasCOI') IS NOT NULL DROP TABLE #AliasCOI;
CREATE TABLE #AliasCOI (nome_norm nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
INSERT INTO #AliasCOI (nome_norm) VALUES (N'COI'), (N'CONTRATO 7/2023 - COI');

-- [R2] Universo: abertos na janela, tipo I/R
IF OBJECT_ID('tempdb..#RegCand') IS NOT NULL DROP TABLE #RegCand;
CREATE TABLE #RegCand (
    id          int            NOT NULL,
    persid      nvarchar(64)   COLLATE DATABASE_DEFAULT NULL,
    ref_num     nvarchar(64)   COLLATE DATABASE_DEFAULT NULL,
    resumo      nvarchar(4000) COLLATE DATABASE_DEFAULT NULL, -- Estruturado ao lado do ref_num
    tipo        char(1)        COLLATE DATABASE_DEFAULT NULL,
    group_id    varbinary(16)  NULL,
    open_date   int            NULL,
    log_agent   varbinary(16)  NULL,
    abertura_br datetime2(0)   NULL,
    fim_excl    int            NULL
);

INSERT INTO #RegCand (id, persid, ref_num, resumo, tipo, group_id, open_date, log_agent, abertura_br, fim_excl)
SELECT
    r.id, r.persid, r.ref_num, 
    r.summary AS resumo,
    r.[type] AS tipo, r.group_id, r.open_date, r.log_agent, br.abertura_br,
    CASE WHEN @HorizonteMensal = 1
         THEN DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, DATEADD(MONTH, DATEDIFF(MONTH, 0, br.abertura_br) + 1, 0)))
         ELSE @FimEpoch
    END AS fim_excl
FROM dbo.call_req AS r
CROSS APPLY (SELECT abertura_br = DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date, @Epoch))) AS br
WHERE r.[type] IN ('I', 'R')
  AND r.open_date >= @InicioEpoch
  AND r.open_date <  @FimEpoch
OPTION (RECOMPILE);

CREATE UNIQUE CLUSTERED INDEX IX_RegCand_id ON #RegCand(id);
CREATE INDEX IX_RegCand_persid ON #RegCand(persid);

-- [R3] Leitura dos logs de transferência
IF OBJECT_ID('tempdb..#RegAtos') IS NOT NULL DROP TABLE #RegAtos;
SELECT
    c.id, al.system_time,
    (CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' ' + CONVERT(nvarchar(max), ISNULL(al.action_desc,  N''))) COLLATE Latin1_General_CI_AI AS texto
INTO #RegAtos
FROM #RegCand AS c
JOIN dbo.act_log AS al ON al.call_req_id = c.persid AND al.[type] = 'TR' AND al.system_time IS NOT NULL
OPTION (RECOMPILE);

CREATE CLUSTERED INDEX IX_RegAtos ON #RegAtos(id, system_time);

-- [R4] Âncora de GRUPO e Parsing do Histórico
IF OBJECT_ID('tempdb..#RegRaw') IS NOT NULL DROP TABLE #RegRaw;
SELECT a.id, a.system_time, CONVERT(nvarchar(400), SUBSTRING(a.texto, anc.posicao, 400)) COLLATE DATABASE_DEFAULT AS resto
INTO #RegRaw
FROM #RegAtos AS a
CROSS APPLY (SELECT p1 = CHARINDEX(N'Grupo de', a.texto), p2 = CHARINDEX(N'Grupo alterado de', a.texto), p3 = CHARINDEX(N'Grupo transferido de', a.texto), p4 = CHARINDEX(N'Group from', a.texto), p5 = CHARINDEX(N'Group changed from', a.texto)) AS pos
CROSS APPLY (SELECT posicao = CASE WHEN pos.p1 > 0 THEN pos.p1 + 8 WHEN pos.p2 > 0 THEN pos.p2 + 17 WHEN pos.p3 > 0 THEN pos.p3 + 20 WHEN pos.p4 > 0 THEN pos.p4 + 10 WHEN pos.p5 > 0 THEN pos.p5 + 18 ELSE 0 END) AS anc
WHERE anc.posicao > 0;

CREATE CLUSTERED INDEX IX_RegRaw ON #RegRaw(id, system_time);

-- [R5] Normalização de Origem e Destino
IF OBJECT_ID('tempdb..#RegEv') IS NOT NULL DROP TABLE #RegEv;
SELECT
    g.id, g.system_time AS evento,
    CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(ori.nome))), N' ', N'<>'), N'><', N''), N'<>', N' ')))) COLLATE DATABASE_DEFAULT AS origem_norm,
    CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(des.nome))), N' ', N'<>'), N'><', N''), N'<>', N' ')))) COLLATE DATABASE_DEFAULT AS destino_norm
INTO #RegEv
FROM #RegRaw AS g
CROSS APPLY (SELECT q1 = CHARINDEX(N'''', g.resto)) AS c1
CROSS APPLY (SELECT q2 = CASE WHEN c1.q1 > 0 THEN CHARINDEX(N'''', g.resto, c1.q1 + 1) ELSE 0 END) AS c2
CROSS APPLY (SELECT nome = CASE WHEN c2.q2 > c1.q1 THEN SUBSTRING(g.resto, c1.q1 + 1, c2.q2 - c1.q1 - 1) ELSE N'' END) AS ori
CROSS APPLY (SELECT posicao = CASE WHEN c2.q2 > 0 AND CHARINDEX(N' para ', g.resto, c2.q2) > 0 THEN CHARINDEX(N' para ', g.resto, c2.q2) WHEN c2.q2 > 0 THEN CHARINDEX(N' to ', g.resto, c2.q2) ELSE 0 END) AS sep
CROSS APPLY (SELECT q3 = CASE WHEN sep.posicao > 0 THEN CHARINDEX(N'''', g.resto, sep.posicao) ELSE 0 END) AS c3
CROSS APPLY (SELECT q4 = CASE WHEN c3.q3 > 0 THEN CHARINDEX(N'''', g.resto, c3.q3 + 1) ELSE 0 END) AS c4
CROSS APPLY (SELECT nome = CASE WHEN c4.q4 > c3.q3 THEN SUBSTRING(g.resto, c3.q3 + 1, c4.q4 - c3.q3 - 1) ELSE N'' END) AS des
WHERE c1.q1 > 0 AND c2.q2 > c1.q1 AND sep.posicao > 0 AND c3.q3 > 0 AND c4.q4 > c3.q3;

CREATE CLUSTERED INDEX IX_RegEv ON #RegEv(id, evento);

-- [R6] Classificação
IF OBJECT_ID('tempdb..#Registrados') IS NOT NULL DROP TABLE #Registrados;
CREATE TABLE #Registrados (
    id              int            NOT NULL,
    SDM             nvarchar(64)   COLLATE DATABASE_DEFAULT NULL,
    resumo          nvarchar(4000) COLLATE DATABASE_DEFAULT NULL, -- Estruturado ao lado do SDM
    tipo            char(1)        COLLATE DATABASE_DEFAULT NULL,
    abertura_br     datetime2(0)   NULL,
    log_agent       varbinary(16)  NULL,
    grupo_atual     varbinary(16)  NULL,
    entrada_coi_br  datetime2(0)   NULL,
    evidencia_coi   varchar(34)    COLLATE DATABASE_DEFAULT NULL,
    alias_evidencia nvarchar(200)  COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #Registrados (id, SDM, resumo, tipo, abertura_br, log_agent, grupo_atual, entrada_coi_br, evidencia_coi, alias_evidencia)
SELECT
    c.id, c.ref_num AS SDM, 
    c.resumo, 
    c.tipo, c.abertura_br, c.log_agent, c.group_id AS grupo_atual, ent.entrada_br AS entrada_coi_br,
    CONVERT(varchar(34), k.evidencia) COLLATE DATABASE_DEFAULT AS evidencia_coi,
    CONVERT(nvarchar(200), k.alias_evidencia) COLLATE DATABASE_DEFAULT AS alias_evidencia
FROM #RegCand AS c
OUTER APPLY (SELECT n = COUNT(*) FROM #RegEv AS e WHERE e.id = c.id) AS ev
OUTER APPLY (SELECT TOP (1) e.origem_norm FROM #RegEv AS e WHERE e.id = c.id AND NULLIF(e.origem_norm, N'') IS NOT NULL ORDER BY e.evento, e.origem_norm) AS ini
OUTER APPLY (SELECT TOP (1) e.destino_norm, entrada_br = DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, e.evento, @Epoch)) FROM #RegEv AS e WHERE e.id = c.id AND e.evento >= c.open_date AND e.evento < c.fim_excl AND EXISTS (SELECT 1 FROM #AliasCOI AS a WHERE a.nome_norm COLLATE Latin1_General_CI_AI = e.destino_norm COLLATE Latin1_General_CI_AI) ORDER BY e.evento, e.destino_norm) AS ent
CROSS APPLY (SELECT ini_eh_coi = CASE WHEN EXISTS (SELECT 1 FROM #AliasCOI AS a WHERE a.nome_norm COLLATE Latin1_General_CI_AI = ini.origem_norm COLLATE Latin1_General_CI_AI) THEN 1 ELSE 0 END) AS f
CROSS APPLY (SELECT
        evidencia = CASE WHEN f.ini_eh_coi = 1 THEN 'GRUPO_INICIAL' WHEN ent.destino_norm IS NOT NULL THEN 'TRANSFERENCIA_PARA_COI' WHEN ev.n = 0 AND c.group_id IN (@COI_Antigo, @COI_Novo) THEN 'FALLBACK_GRUPO_ATUAL_SEM_HISTORICO' ELSE 'NAO_ENTRA' END,
        alias_evidencia = CASE WHEN f.ini_eh_coi = 1 THEN ini.origem_norm WHEN ent.destino_norm IS NOT NULL THEN ent.destino_norm WHEN ev.n = 0 AND c.group_id = @COI_Antigo THEN N'(fallback UUID COI_Antigo)' WHEN ev.n = 0 AND c.group_id = @COI_Novo THEN N'(fallback UUID COI_Novo)' ELSE NULL END) AS k
WHERE k.evidencia <> 'NAO_ENTRA';

CREATE CLUSTERED INDEX IX_Registrados ON #Registrados(id);

--------------------------------------------------------------------------------
-- [JANELA 1] MENSAL (GRÁFICO 1)
--------------------------------------------------------------------------------
IF (@G1_Mensal = 1 OR @ResultadoTudo = 1)
BEGIN
    IF OBJECT_ID('tempdb..#Dias') IS NOT NULL DROP TABLE #Dias;
    SELECT TOP (DATEDIFF(DAY, @InicioBR, @FimBR)) CONVERT(date, DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, @InicioBR)) AS dia
    INTO #Dias FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

    IF OBJECT_ID('tempdb..#Meses') IS NOT NULL DROP TABLE #Meses;
    SELECT DISTINCT YEAR(d.dia) AS Ano, MONTH(d.dia) AS Mes, CONVERT(char(7), CONCAT(YEAR(d.dia), N'-', RIGHT(CONCAT(N'0', MONTH(d.dia)), 2))) AS MesAno
    INTO #Meses FROM #Dias AS d;

    SELECT 
        'Visão Gráfico Mensal' AS Indicador,
        m.Ano, m.Mes, m.MesAno,
        ISNULL(agg.Incidentes,   0) AS Incidentes,
        ISNULL(agg.Solicitacoes, 0) AS Solicitacoes,
        ISNULL(agg.Total,        0) AS Total
    FROM #Meses AS m
    OUTER APPLY (
        SELECT SUM(CASE WHEN r.tipo = 'I' THEN 1 ELSE 0 END) AS Incidentes,
               SUM(CASE WHEN r.tipo = 'R' THEN 1 ELSE 0 END) AS Solicitacoes,
               COUNT(*) AS Total
        FROM #Registrados AS r
        WHERE YEAR(r.abertura_br)   = m.Ano AND MONTH(r.abertura_br) = m.Mes
    ) AS agg
    ORDER BY m.Ano, m.Mes;
END

--------------------------------------------------------------------------------
-- [JANELA 2] DETALHES (AUDITORIA LINHA A LINHA)
--------------------------------------------------------------------------------
IF (@Detalhes = 1 OR @ResultadoTudo = 1)
BEGIN
    SELECT 
        'Visão Detalhes (Auditoria)' AS Indicador,
        r.SDM,
        r.resumo                                        AS Resumo, -- Posicionado na saída logo ao lado do SDM
        r.abertura_br                                   AS DataHoraRegistro,
        CONVERT(date, r.abertura_br)                    AS DataRegistro,
        DATEPART(HOUR, r.abertura_br)                   AS HoraRegistro,
        r.tipo                                          AS TipoCodigo,
        CASE r.tipo WHEN 'I' THEN N'Incidente' WHEN 'R' THEN N'Solicitação' ELSE N'N/A' END AS Tipo,
        r.log_agent                                     AS RegistradorUUID,
        ISNULL(NULLIF(LTRIM(RTRIM(reg.userid)), N''), N'(não resolvido)') AS RegistradorUserID,
        CASE
            WHEN r.log_agent IS NULL THEN N'(sem registrador no chamado)'
            WHEN reg.contact_uuid IS NULL THEN N'(UUID sem contato em ca_contact)'
            WHEN (ISNULL(reg.first_name, N'') <> N'' OR ISNULL(reg.last_name, N'') <> N'') 
                THEN LTRIM(RTRIM(CONCAT(ISNULL(reg.first_name, N''), N' ', ISNULL(reg.last_name, N''))))
            WHEN ISNULL(reg.userid, N'') <> N'' THEN reg.userid
            ELSE N'(contato sem nome)'
        END                                             AS RegistradorNome,
        r.grupo_atual                                   AS GrupoAtualUUID,
        r.evidencia_coi                                 AS EvidenciaCOI,
        ISNULL(r.alias_evidencia, N'-')                 AS AliasEvidencia,
        r.entrada_coi_br                                AS DataPrimeiraEntradaCOI
    FROM #Registrados AS r
    LEFT JOIN dbo.ca_contact AS reg ON reg.contact_uuid = r.log_agent
    ORDER BY r.abertura_br, r.SDM;
END