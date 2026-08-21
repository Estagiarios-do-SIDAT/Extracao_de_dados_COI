USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- GRÁFICO 1: Chamados Registrados pelo COI (Mensal)
-- Total de chamados abertos no mês, agrupados por mês, com coluna
-- separada para Incidentes (I) e Solicitações (R).
--------------------------------------------------------------------------------

DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch              datetime2(0) = '1970-01-01 00:00:00';

-- Período de análise em UTC (horário do Brasil + 3h)
DECLARE @InicioAnoBR  datetime2(0) = '2025-03-01 00:00:00'; -- início desejado (horário BR)
DECLARE @FimAnoBR     datetime2(0) = '2026-03-31 23:59:59'; -- fim desejado    (horário BR)

DECLARE @InicioUTC datetime2(0) = DATEADD(HOUR,  @HorasBrasilParaUTC, @InicioAnoBR);
DECLARE @FimUTC    datetime2(0) = DATEADD(HOUR,  @HorasBrasilParaUTC, @FimAnoBR);

DECLARE @InicioEpoch int = DATEDIFF(SECOND, @Epoch, @InicioUTC);
DECLARE @FimEpoch    int = DATEDIFF(SECOND, @Epoch, @FimUTC);

-- Grupos COI (Antigo e Novo)
DECLARE @COI_Antigo varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;
DECLARE @COI_Novo   varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;

--------------------------------------------------------------------------------
-- [BASE ABERTOS] Chamados com open_date no período
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Abertos') IS NOT NULL DROP TABLE #Abertos;

SELECT
    r.id,
    r.ref_num,
    r.[type],
    r.open_date,
    r.close_date,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date, @Epoch)) AS open_br
INTO #Abertos
FROM dbo.call_req AS r
WHERE r.group_id IN (@COI_Antigo, @COI_Novo)
  AND r.[type] IN ('I', 'R')
  AND r.open_date IS NOT NULL
  AND r.open_date >= @InicioEpoch
  AND r.open_date <= @FimEpoch;

CREATE INDEX IX_Abertos_open ON #Abertos(open_date);
CREATE INDEX IX_Abertos_type ON #Abertos([type]);

--------------------------------------------------------------------------------
-- [GRÁFICO 1] Consulta Final
--------------------------------------------------------------------------------
SELECT
    YEAR(a.open_br)                         AS Ano,
    MONTH(a.open_br)                        AS Mes,
    UPPER(LEFT(DATENAME(MONTH, a.open_br), 3))
        + N'/' + RIGHT(CONVERT(char(4), YEAR(a.open_br)), 2) AS MesAno,
    SUM(CASE WHEN a.[type] = 'I' THEN 1 ELSE 0 END) AS Incidentes,
    SUM(CASE WHEN a.[type] = 'R' THEN 1 ELSE 0 END) AS Solicitacoes,
    COUNT(*)                                AS Total
FROM #Abertos AS a
GROUP BY
    YEAR(a.open_br),
    MONTH(a.open_br),
    UPPER(LEFT(DATENAME(MONTH, a.open_br), 3))
        + N'/' + RIGHT(CONVERT(char(4), YEAR(a.open_br)), 2)
ORDER BY
    YEAR(a.open_br),
    MONTH(a.open_br);
