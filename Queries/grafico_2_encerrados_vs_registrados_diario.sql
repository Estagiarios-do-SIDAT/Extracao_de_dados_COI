USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- GRÁFICO 2: Chamados Encerrados vs Registrados por dia
-- Contagem diária de chamados abertos (registrados) e fechados
-- (encerrados) pelo COI dentro do período.
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
-- [BASE ABERTOS]
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

--------------------------------------------------------------------------------
-- [BASE ENCERRADOS]
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Encerrados') IS NOT NULL DROP TABLE #Encerrados;

SELECT
    r.id,
    r.ref_num,
    r.[type],
    r.open_date,
    r.close_date,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.close_date, @Epoch)) AS close_br
INTO #Encerrados
FROM dbo.call_req AS r
WHERE r.group_id IN (@COI_Antigo, @COI_Novo)
  AND r.[type] IN ('I', 'R')
  AND r.close_date IS NOT NULL
  AND r.close_date >= @InicioEpoch
  AND r.close_date <= @FimEpoch;

CREATE INDEX IX_Encerrados_close ON #Encerrados(close_date);

--------------------------------------------------------------------------------
-- [GRÁFICO 2] Consulta Final
--------------------------------------------------------------------------------
;WITH DiasMovimento AS (
    SELECT CAST(a.open_br  AS date) AS dia FROM #Abertos    AS a
    UNION
    SELECT CAST(e.close_br AS date) AS dia FROM #Encerrados AS e
)
SELECT
    dm.dia                                              AS Dia,
    ISNULL(reg.QtdRegistrados, 0)                       AS Registrados,
    ISNULL(enc.QtdEncerrados,  0)                       AS Encerrados
FROM DiasMovimento AS dm
LEFT JOIN (
    SELECT
        CAST(a.open_br AS date) AS dia,
        COUNT(*)                AS QtdRegistrados
    FROM #Abertos AS a
    GROUP BY CAST(a.open_br AS date)
) AS reg ON reg.dia = dm.dia
LEFT JOIN (
    SELECT
        CAST(e.close_br AS date) AS dia,
        COUNT(*)                  AS QtdEncerrados
    FROM #Encerrados AS e
    GROUP BY CAST(e.close_br AS date)
) AS enc ON enc.dia = dm.dia
ORDER BY
    dm.dia;
