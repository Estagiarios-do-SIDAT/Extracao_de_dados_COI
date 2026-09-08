USE mdb;
SET NOCOUNT ON;

/*
================================================================================
COI - Chamados REGISTRADOS pelo COI, por hora do dia
Abordagem: Gráfico 1 (Filtro direto pelo group_id atual, sem ler act_log)
================================================================================
*/

DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';

-- Período analisado (Intervalo SEMIABERTO: >= início e < fim)
DECLARE @InicioBR datetime2(0) = '2026-03-09 00:00:00';   -- inclusivo
DECLARE @FimBR    datetime2(0) = '2026-03-31 23:59:59';   -- EXCLUSIVO

DECLARE @InicioEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @InicioBR));
DECLARE @FimEpoch    int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @FimBR));

-- Identidade do COI por UUID (Grupos Antigo e Novo)
DECLARE @COI_Antigo varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;
DECLARE @COI_Novo   varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;

--------------------------------------------------------------------------------
-- 1. BASE ABERTOS (Usando a regra simplificada do Gráfico 1)
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Abertos') IS NOT NULL DROP TABLE #Abertos;

SELECT
    r.id,
    r.ref_num,
    r.[type],
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date, @Epoch)) AS abertura_br
INTO #Abertos
FROM dbo.call_req AS r
WHERE r.group_id IN (@COI_Antigo, @COI_Novo)
  AND r.[type] IN ('I', 'R')
  AND r.open_date IS NOT NULL
  AND r.open_date >= @InicioEpoch
  AND r.open_date <  @FimEpoch;

CREATE CLUSTERED INDEX IX_Abertos_abertura ON #Abertos(abertura_br);

--------------------------------------------------------------------------------
-- 2. CALENDÁRIO (Garante que todas as 24h apareçam para cada mês)
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Dias') IS NOT NULL DROP TABLE #Dias;

SELECT TOP (DATEDIFF(DAY, @InicioBR, @FimBR))
    CONVERT(date, DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, @InicioBR)) AS dia
INTO #Dias
FROM sys.all_objects AS a
CROSS JOIN sys.all_objects AS b;

IF OBJECT_ID('tempdb..#Meses') IS NOT NULL DROP TABLE #Meses;

SELECT DISTINCT
    YEAR(d.dia)  AS Ano,
    MONTH(d.dia) AS Mes,
    CONVERT(char(7), CONCAT(YEAR(d.dia), N'-', RIGHT(CONCAT(N'0', MONTH(d.dia)), 2))) AS MesAno
INTO #Meses
FROM #Dias AS d;

IF OBJECT_ID('tempdb..#Horas') IS NOT NULL DROP TABLE #Horas;

SELECT TOP (24)
    CONVERT(int, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1) AS Hora
INTO #Horas
FROM sys.all_objects AS a;

--------------------------------------------------------------------------------
-- 3. RESULTADO FINAL (Agrupamento por Ano, Mês e Hora)
--------------------------------------------------------------------------------
SELECT
    m.Ano,
    m.Mes,
    m.MesAno,
    h.Hora,
    CONVERT(char(3), CONCAT(RIGHT(CONCAT(N'0', h.Hora), 2), N'h')) AS HoraLabel,
    ISNULL(agg.Qtd, 0) AS QtdRegistrados
FROM #Meses AS m
CROSS JOIN #Horas AS h
OUTER APPLY (
    SELECT COUNT(*) AS Qtd
    FROM #Abertos AS a
    WHERE YEAR(a.abertura_br)           = m.Ano
      AND MONTH(a.abertura_br)          = m.Mes
      AND DATEPART(HOUR, a.abertura_br) = h.Hora
) AS agg
ORDER BY
    m.Ano,
    m.Mes,
    h.Hora;