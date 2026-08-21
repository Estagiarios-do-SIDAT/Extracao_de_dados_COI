USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- GRÁFICO 3: Chamados Registrados por Hora (Mês Anterior e Mês Vigente)
-- Contagem de chamados agrupados por hora de abertura (00h-23h),
-- retornando mês anterior e mês vigente separadamente.
--------------------------------------------------------------------------------

DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch              datetime2(0) = '1970-01-01 00:00:00';

-- Mês vigente (mês atual) e mês anterior
DECLARE @InicioMesVigenteUTC datetime2(0) =
    DATEADD(HOUR, @HorasBrasilParaUTC,
        CAST(DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1) AS datetime2(0)));

DECLARE @FimMesVigenteUTC datetime2(0) =
    DATEADD(SECOND, -1,
        DATEADD(MONTH, 1, @InicioMesVigenteUTC));

DECLARE @InicioMesAnteriorUTC datetime2(0) =
    DATEADD(MONTH, -1, @InicioMesVigenteUTC);

DECLARE @FimMesAnteriorUTC datetime2(0) =
    DATEADD(SECOND, -1, @InicioMesVigenteUTC);

DECLARE @InicioMesVigenteEpoch  int = DATEDIFF(SECOND, @Epoch, @InicioMesVigenteUTC);
DECLARE @FimMesVigenteEpoch     int = DATEDIFF(SECOND, @Epoch, @FimMesVigenteUTC);
DECLARE @InicioMesAnteriorEpoch int = DATEDIFF(SECOND, @Epoch, @InicioMesAnteriorUTC);
DECLARE @FimMesAnteriorEpoch    int = DATEDIFF(SECOND, @Epoch, @FimMesAnteriorUTC);

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
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date, @Epoch)) AS open_br
INTO #Abertos
FROM dbo.call_req AS r
WHERE r.group_id IN (@COI_Antigo, @COI_Novo)
  AND r.[type] IN ('I', 'R')
  AND r.open_date IS NOT NULL
  AND r.open_date >= @InicioMesAnteriorEpoch
  AND r.open_date <= @FimMesVigenteEpoch;

CREATE INDEX IX_Abertos_open ON #Abertos(open_date);

--------------------------------------------------------------------------------
-- [GRÁFICO 3A] Chamados Registrados por Hora — Mês Anterior
--------------------------------------------------------------------------------
SELECT
    DATEPART(HOUR, a.open_br)  AS Hora,
    RIGHT('0' + CONVERT(varchar(2), DATEPART(HOUR, a.open_br)), 2) + N'h' AS HoraLabel,
    COUNT(*)                   AS QtdChamados
FROM #Abertos AS a
WHERE a.open_date >= @InicioMesAnteriorEpoch
  AND a.open_date <= @FimMesAnteriorEpoch
GROUP BY
    DATEPART(HOUR, a.open_br)
ORDER BY
    DATEPART(HOUR, a.open_br);

--------------------------------------------------------------------------------
-- [GRÁFICO 3B] Chamados Registrados por Hora — Mês Vigente
--------------------------------------------------------------------------------
SELECT
    DATEPART(HOUR, a.open_br)  AS Hora,
    RIGHT('0' + CONVERT(varchar(2), DATEPART(HOUR, a.open_br)), 2) + N'h' AS HoraLabel,
    COUNT(*)                   AS QtdChamados
FROM #Abertos AS a
WHERE a.open_date >= @InicioMesVigenteEpoch
  AND a.open_date <= @FimMesVigenteEpoch
GROUP BY
    DATEPART(HOUR, a.open_br)
ORDER BY
    DATEPART(HOUR, a.open_br);
