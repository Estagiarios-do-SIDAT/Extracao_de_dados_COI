USE mdb;
SET NOCOUNT ON;

/*
================================================================================
COI - REGISTRADOS POR MEMBROS HUMANOS DO COI
================================================================================

A REGRA, INTEIRA

        open_date na janela
        AND type IN ('I','R')
        AND log_agent pertence ao ROSTER HISTORICO do COI naquele periodo

    E so isso. Sem filtro de grupo, sem act_log, sem group_id, sem status,
    prioridade, SLA, customer ou canal.

    Foi esta regra que reproduziu EXATAMENTE as Solicitacoes publicadas pelo
    fornecedor em fevereiro, marco e junho de 2026 - 436, 717 e 466 -, cada uma
    por dois caminhos independentes. E a parte mais bem estabelecida de toda a
    apuracao de Registrados, e nao se mexe nela sem prova nova.

ROSTER HISTORICO, NUNCA dbo.grpmem

    Os nomes vem da tabela por analista (DADOS!M:P) do RSP de cada mes:

        FEV  25 analistas    MAR  26 analistas    JUN  28 analistas

    dbo.grpmem NAO aparece neste arquivo. Ele guarda a composicao ATUAL da
    equipe; usa-lo aqui trocaria o quadro do periodo pelo de hoje, e a equipe
    mudou entre esses meses - foi por isso que marco caiu como periodo de
    validacao numa rodada anterior.

    As colunas S_RSP e I_RSP do RS 2 sao o que o RSP publica para cada analista.
    Sao REFERENCIA de conferencia: nenhum predicado deste arquivo as utiliza.

CONTAS TECNICAS NAO ENTRAM AQUI

    ServiceDesk, usr_automacoes e sesuc_auto sao compartilhadas com outros
    nucleos e nao pertencem ao COI por si. Elas sao tratadas, com exigencia de
    prova de origem, em:

        coi/queries/consulta_coi_registrados_total_com_tecnicos.sql
        coi/queries/consulta_coi_registrados_universo_bruto.sql

REFERENCIA DE VALIDACAO (medida, nao codificada em predicado)

        FEV  I=129  R=436  Total=565
        MAR  I=141  R=717  Total=858
        JUN  I=99   R=466  Total=565

MARCO E 09/03 A 31/03: e o intervalo que o RSP daquele mes cobre.

SOMENTE LEITURA. Batch unico, sem GO. 3 result sets.
================================================================================
*/

--------------------------------------------------------------------------------
-- [0] PARAMETROS - PERIODOS. EDITE AQUI. Fim SEMPRE exclusivo.
--------------------------------------------------------------------------------
DECLARE @H int = 3;                                  -- Brasil -> UTC
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';

IF OBJECT_ID('tempdb..#Per') IS NOT NULL DROP TABLE #Per;
CREATE TABLE #Per (
    ord     int NOT NULL PRIMARY KEY,
    periodo char(3) COLLATE DATABASE_DEFAULT NOT NULL UNIQUE,
    ano     int NOT NULL,
    mes     int NOT NULL,
    ini_e   int NOT NULL,
    fim_e   int NOT NULL
);
INSERT INTO #Per (ord, periodo, ano, mes, ini_e, fim_e)
SELECT p.ord, p.periodo, YEAR(p.ini), MONTH(p.ini),
       DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @H, p.ini)),
       DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @H, p.fim))
FROM (VALUES
    (1, 'FEV', CONVERT(datetime2(0), '2026-02-01'), CONVERT(datetime2(0), '2026-03-01')),
    (2, 'MAR', CONVERT(datetime2(0), '2026-03-09'), CONVERT(datetime2(0), '2026-04-01')),
    (3, 'JUN', CONVERT(datetime2(0), '2026-06-01'), CONVERT(datetime2(0), '2026-07-01'))
) AS p(ord, periodo, ini, fim);

DECLARE @MinE int = (SELECT MIN(ini_e) FROM #Per);
DECLARE @MaxE int = (SELECT MAX(fim_e) FROM #Per);

--------------------------------------------------------------------------------
-- [1] ROSTER HISTORICO POR PERIODO
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Roster') IS NOT NULL DROP TABLE #Roster;
CREATE TABLE #Roster (
    periodo char(3) COLLATE DATABASE_DEFAULT NOT NULL,
    nome    nvarchar(120) COLLATE DATABASE_DEFAULT NOT NULL,
    s_rsp   int NOT NULL,
    i_rsp   int NOT NULL,
    PRIMARY KEY (periodo, nome)
);
INSERT INTO #Roster (periodo, nome, s_rsp, i_rsp) VALUES
    (N'FEV', N'Adjanir Jorge Amazonas da Silva', 0, 3),
    (N'FEV', N'Alessandra Liermann Torres', 4, 0),
    (N'FEV', N'Anderson Garcia Reis', 0, 0),
    (N'FEV', N'Bruno Hiago da Costa Pinto', 10, 38),
    (N'FEV', N'Bruno Souza Mello Viscardi', 42, 22),
    (N'FEV', N'Cristiano Caldeira Pirangi', 56, 24),
    (N'FEV', N'Edson Levi Tomaz Junior', 0, 0),
    (N'FEV', N'Elásio Alberto de Oliveira Rondon Junior', 0, 0),
    (N'FEV', N'Elton Freitas de Santana', 43, 47),
    (N'FEV', N'Francisco Danilo Fontenele Lima', 66, 35),
    (N'FEV', N'Gabriel Ribeiro Valente Damiani', 20, 0),
    (N'FEV', N'Gleuton Luiz Alves de Oliveira', 24, 41),
    (N'FEV', N'Jean Henrique Ferreira Pires', 0, 0),
    (N'FEV', N'Luan Barbosa Rodrigues', 17, 16),
    (N'FEV', N'Lucas dos Santos do Amaral', 0, 0),
    (N'FEV', N'Lucas Icaro Faria Pacheco de Carvalho', 27, 33),
    (N'FEV', N'Marco Aurélio Matias Alves', 0, 0),
    (N'FEV', N'Pedro Henrique Dias Barbosa', 0, 0),
    (N'FEV', N'Pedro Victor Luz Garcia', 0, 0),
    (N'FEV', N'Pitagoras Henrique de Sousa Mota', 7, 10),
    (N'FEV', N'Raphael Alexander Maciel da Silva', 0, 0),
    (N'FEV', N'Thiago Pereira Passos de Araújo Silva', 0, 0),
    (N'FEV', N'Vamberto Freire da Silva', 84, 56),
    (N'FEV', N'Vinicius de Morais Cardoso Tinoco', 28, 1),
    (N'FEV', N'Wendel Brito de Oliveira', 8, 44),
    (N'MAR', N'Adjanir Jorge Amazonas da Silva', 22, 14),
    (N'MAR', N'Bruno Hiago da Costa Pinto', 206, 0),
    (N'MAR', N'Bruno Roberto Costa Oliveira', 0, 0),
    (N'MAR', N'Bruno Souza Mello Viscardi', 80, 51),
    (N'MAR', N'Cristiano Caldeira Pirangi', 8, 4),
    (N'MAR', N'Elasio Alberto de Oliveira Rondon Junior', 0, 0),
    (N'MAR', N'Elton Freitas de Santana', 90, 66),
    (N'MAR', N'Felipe Alves dos Santos', 2, 36),
    (N'MAR', N'Francisco Danilo Fontenele Lima', 49, 54),
    (N'MAR', N'Gabriel Santos Moraes', 13, 0),
    (N'MAR', N'George do Nascimento Mota', 1, 33),
    (N'MAR', N'Jean Henrique Ferreira Pires', 3, 0),
    (N'MAR', N'Klebson Macedo de Oliveira', 0, 0),
    (N'MAR', N'Luan Barbosa Rodrigues', 13, 18),
    (N'MAR', N'Lucas dos Santos Amaral', 6, 4),
    (N'MAR', N'Lucas Icaro Faria Pacheco de Carvalho', 53, 49),
    (N'MAR', N'Marcella Coimbra de Brito', 36, 0),
    (N'MAR', N'Marcelo Pereira Avelino', 7, 17),
    (N'MAR', N'Marco Aurélio Matias Alves', 2, 38),
    (N'MAR', N'Pedro Henrique Dias Barbosa', 2, 1),
    (N'MAR', N'Pedro Antônio Marques da Silva', 0, 20),
    (N'MAR', N'Raphael Alexander Maciel da Silva', 0, 0),
    (N'MAR', N'Vamberto Freire da Silva', 29, 65),
    (N'MAR', N'Vinicius de Morais Cardoso Tinoco', 40, 11),
    (N'MAR', N'Wanderson Alencar da Cruz', 0, 0),
    (N'MAR', N'Wendel Brito de Oliveira', 55, 14),
    (N'JUN', N'Adjanir Jorge Amazonas da Silva', 8, 2),
    (N'JUN', N'Bruno Hiago da Costa Pinto', 85, 0),
    (N'JUN', N'Bruno Roberto Costa de Oliveira', 0, 0),
    (N'JUN', N'Bruno Souza Mello Viscardi', 19, 24),
    (N'JUN', N'Eduardo de Araujo Ferreira', 34, 21),
    (N'JUN', N'Elásio Alberto de Oliveira Rondon Junior', 2, 0),
    (N'JUN', N'Elton Freitas de Santana', 25, 33),
    (N'JUN', N'Felipe Alves dos Santos', 14, 34),
    (N'JUN', N'Francisco Danilo Fontenele Lima', 30, 41),
    (N'JUN', N'Gabriel Santos Moraes', 59, 0),
    (N'JUN', N'George do Nascimento Mota', 0, 5),
    (N'JUN', N'Jean Henrique Ferreira Pires', 0, 0),
    (N'JUN', N'Klebson Macedo de Oliveira', 0, 0),
    (N'JUN', N'Luan Barbosa Rodrigues', 6, 15),
    (N'JUN', N'Lucas dos Santos do Amaral', 1, 0),
    (N'JUN', N'Lucas Icaro Faria Pacheco de Carvalho', 19, 34),
    (N'JUN', N'Marcella Coimbra de Brito', 3, 0),
    (N'JUN', N'Marcelo Pereira Avelino', 1, 27),
    (N'JUN', N'Marco Aurélio Matias Alves', 0, 0),
    (N'JUN', N'Pedro Rafael de Oliveira Carvalho', 15, 3),
    (N'JUN', N'Pedro Henrique Dias Barbosa', 2, 0),
    (N'JUN', N'Raphael Alexander Maciel da Silva', 0, 0),
    (N'JUN', N'Vamberto Freire da Silva', 30, 38),
    (N'JUN', N'Vinicius de Morais Cardoso Tinoco', 4, 0),
    (N'JUN', N'Wanderson Alencar da Cruz', 0, 0),
    (N'JUN', N'Wendel Brito de Oliveira', 2, 0),
    (N'JUN', N'Thays da Silva Guerra', 93, 0),
    (N'JUN', N'Julio Cesár de Lacerda Jr.', 14, 32);

--------------------------------------------------------------------------------
-- [2] CONTATOS NORMALIZADOS E CASAMENTO nome do RSP -> contato
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#ContNorm') IS NOT NULL DROP TABLE #ContNorm;
SELECT
    c.contact_uuid,
    CONVERT(nvarchar(120), LTRIM(RTRIM(CONCAT(ISNULL(c.first_name, N''), N' ', ISNULL(c.last_name, N'')))))
        COLLATE DATABASE_DEFAULT AS nome_bruto,
    CONVERT(nvarchar(120), ISNULL(c.userid, N'')) COLLATE DATABASE_DEFAULT AS userid,
    CONVERT(nvarchar(120), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(CONCAT(ISNULL(c.first_name, N''), N' ', ISNULL(c.last_name, N'')), N'.', N' '), N'-', N' '), CHAR(39), N' '), N',', N' ')))), N' ', N'<>'), N'><', N''), N'<>', N' ')))) COLLATE DATABASE_DEFAULT AS n_basico,
    CONVERT(nvarchar(120), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(N' ' + LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(CONCAT(ISNULL(c.first_name, N''), N' ', ISNULL(c.last_name, N'')), N'.', N' '), N'-', N' '), CHAR(39), N' '), N',', N' ')))), N' ', N'<>'), N'><', N''), N'<>', N' '))) + N' ', N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' JR ', N' JUNIOR '), N' ', N'<>'), N'><', N''), N'<>', N' '))))   COLLATE DATABASE_DEFAULT AS n_part
INTO #ContNorm
FROM dbo.ca_contact AS c;
CREATE CLUSTERED INDEX IX_ContNorm ON #ContNorm(contact_uuid);
CREATE INDEX IX_ContNorm_p ON #ContNorm(n_part);

IF OBJECT_ID('tempdb..#Match') IS NOT NULL DROP TABLE #Match;
SELECT k.periodo, k.nome, k.contact_uuid, k.prio
INTO #Match
FROM (
    SELECT r.periodo, r.nome, c.contact_uuid, 1 AS prio
    FROM #Roster AS r JOIN #ContNorm AS c
      ON c.n_basico COLLATE Latin1_General_CI_AI = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(r.nome, N'.', N' '), N'-', N' '), CHAR(39), N' '), N',', N' ')))), N' ', N'<>'), N'><', N''), N'<>', N' '))) COLLATE Latin1_General_CI_AI
    UNION
    SELECT r.periodo, r.nome, c.contact_uuid, 2
    FROM #Roster AS r JOIN #ContNorm AS c
      ON c.n_part COLLATE Latin1_General_CI_AI = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(N' ' + LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(r.nome, N'.', N' '), N'-', N' '), CHAR(39), N' '), N',', N' ')))), N' ', N'<>'), N'><', N''), N'<>', N' '))) + N' ', N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' JR ', N' JUNIOR '), N' ', N'<>'), N'><', N''), N'<>', N' '))) COLLATE Latin1_General_CI_AI
    UNION
    SELECT r.periodo, r.nome, c.contact_uuid, 3
    FROM #Roster AS r JOIN #ContNorm AS c
      ON LEN(c.n_part) > 8 AND LEN(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(N' ' + LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(r.nome, N'.', N' '), N'-', N' '), CHAR(39), N' '), N',', N' ')))), N' ', N'<>'), N'><', N''), N'<>', N' '))) + N' ', N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' JR ', N' JUNIOR '), N' ', N'<>'), N'><', N''), N'<>', N' ')))) > 8
     AND (LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(N' ' + LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(r.nome, N'.', N' '), N'-', N' '), CHAR(39), N' '), N',', N' ')))), N' ', N'<>'), N'><', N''), N'<>', N' '))) + N' ', N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' JR ', N' JUNIOR '), N' ', N'<>'), N'><', N''), N'<>', N' '))) COLLATE Latin1_General_CI_AI LIKE c.n_part COLLATE Latin1_General_CI_AI + N'%'
       OR c.n_part COLLATE Latin1_General_CI_AI LIKE LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(N' ' + LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(r.nome, N'.', N' '), N'-', N' '), CHAR(39), N' '), N',', N' ')))), N' ', N'<>'), N'><', N''), N'<>', N' '))) + N' ', N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' DOS ', N' '), N' DAS ', N' '), N' DO ', N' '), N' DA ', N' '), N' DE ', N' '), N' JR ', N' JUNIOR '), N' ', N'<>'), N'><', N''), N'<>', N' '))) COLLATE Latin1_General_CI_AI + N'%')
) AS k;

-- Um contato resolve para UM nome por periodo: a chave unica garante que o
-- JOIN da populacao nao multiplique chamado.
IF OBJECT_ID('tempdb..#RosterUuid') IS NOT NULL DROP TABLE #RosterUuid;
SELECT z.periodo, z.contact_uuid, z.nome
INTO #RosterUuid
FROM (
    SELECT m.periodo, m.contact_uuid, m.nome,
           rn = ROW_NUMBER() OVER (PARTITION BY m.periodo, m.contact_uuid ORDER BY m.prio, m.nome)
    FROM #Match AS m
    JOIN (SELECT periodo, nome, prio = MIN(prio) FROM #Match GROUP BY periodo, nome) AS b
      ON b.periodo = m.periodo AND b.nome = m.nome AND b.prio = m.prio
) AS z
WHERE z.rn = 1;
CREATE UNIQUE CLUSTERED INDEX IX_RosterUuid ON #RosterUuid(periodo, contact_uuid);

--------------------------------------------------------------------------------
-- [3] POPULACAO - uma linha por SDM
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Pop') IS NOT NULL DROP TABLE #Pop;

SELECT
    r.id, r.ref_num AS sdm, r.[type] AS tipo, r.log_agent,
    DATEADD(HOUR, -@H, DATEADD(SECOND, r.open_date, @Epoch)) AS abertura_br,
    pe.periodo, pe.ano, pe.mes, ru.nome AS nome_analista
INTO #Pop
FROM dbo.call_req AS r
CROSS APPLY (
    SELECT TOP (1) p.periodo, p.ano, p.mes FROM #Per AS p
    WHERE r.open_date >= p.ini_e AND r.open_date < p.fim_e
    ORDER BY p.ord
) AS pe
JOIN #RosterUuid AS ru ON ru.periodo = pe.periodo AND ru.contact_uuid = r.log_agent
WHERE r.[type] IN ('I', 'R')
  AND r.open_date >= @MinE
  AND r.open_date <  @MaxE
OPTION (RECOMPILE);

CREATE UNIQUE CLUSTERED INDEX IX_Pop ON #Pop(id);

--------------------------------------------------------------------------------
-- RS 1 - RESUMO POR PERIODO.
--        Linhas x SDMsDistintos e a assercao de unicidade; Duplicados = 0.
--------------------------------------------------------------------------------
SELECT
    p.periodo AS Periodo,
    p.ano AS Ano,
    p.mes AS Mes,
    N'MEMBRO_COI' AS Tipo,
    SUM(CASE WHEN o.tipo = 'I' THEN 1 ELSE 0 END) AS Incidentes,
    SUM(CASE WHEN o.tipo = 'R' THEN 1 ELSE 0 END) AS Solicitacoes,
    COUNT(o.id) AS Total,
    COUNT(DISTINCT o.nome_analista) AS QtdAnalistasComChamado,
    COUNT(o.id) AS Linhas,
    COUNT(DISTINCT o.sdm) AS SDMsDistintos,
    COUNT(o.id) - COUNT(DISTINCT o.sdm) AS Duplicados,
    (SELECT COUNT(*)      FROM #Roster AS rr WHERE rr.periodo = p.periodo) AS AnalistasNoRosterRSP,
    (SELECT SUM(rr.s_rsp) FROM #Roster AS rr WHERE rr.periodo = p.periodo) AS S_RSP_referencia,
    (SELECT SUM(rr.i_rsp) FROM #Roster AS rr WHERE rr.periodo = p.periodo) AS I_RSP_referencia
FROM #Per AS p
LEFT JOIN #Pop AS o ON o.periodo = p.periodo
GROUP BY p.ord, p.periodo, p.ano, p.mes
ORDER BY p.ord;

--------------------------------------------------------------------------------
-- RS 2 - AUDITORIA POR ANALISTA.
--
-- Analista do roster sem chamado aparece com zero, e nome que nao resolveu vem
-- rotulado: sem isso, uma falha de casamento se disfarcaria de analista que
-- simplesmente nao registrou nada.
--------------------------------------------------------------------------------
SELECT
    r.periodo AS Periodo,
    p.ano AS Ano,
    p.mes AS Mes,
    r.nome AS Nome,
    ISNULL(NULLIF(MAX(cn.userid), N''), N'-') AS LogAgent,
    ISNULL(q.i, 0) AS Incidentes,
    ISNULL(q.s, 0) AS Solicitacoes,
    ISNULL(q.t, 0) AS Total,
    r.i_rsp AS I_RSP_referencia,
    r.s_rsp AS S_RSP_referencia,
    CASE WHEN MAX(ru.contact_uuid) IS NULL
         THEN N'nome nao resolvido em ca_contact' ELSE N'' END AS Observacao
FROM #Roster AS r
JOIN #Per AS p ON p.periodo = r.periodo
LEFT JOIN #RosterUuid AS ru ON ru.periodo = r.periodo AND ru.nome = r.nome
LEFT JOIN #ContNorm   AS cn ON cn.contact_uuid = ru.contact_uuid
OUTER APPLY (
    SELECT i = SUM(CASE WHEN o.tipo = 'I' THEN 1 ELSE 0 END),
           s = SUM(CASE WHEN o.tipo = 'R' THEN 1 ELSE 0 END),
           t = COUNT(*)
    FROM #Pop AS o
    WHERE o.periodo = r.periodo AND o.nome_analista = r.nome
) AS q
GROUP BY p.ord, r.periodo, p.ano, p.mes, r.nome, r.i_rsp, r.s_rsp, q.i, q.s, q.t
ORDER BY p.ord, ISNULL(q.t, 0) DESC, r.nome;

--------------------------------------------------------------------------------
-- RS 3 - DETALHE, uma linha por SDM antes de qualquer agregacao
--------------------------------------------------------------------------------
SELECT
    o.periodo AS Periodo,
    o.ano AS Ano,
    o.mes AS Mes,
    o.sdm AS SDM,
    o.abertura_br AS DataAbertura,
    CASE o.tipo WHEN 'I' THEN N'Incidente' ELSE N'Solicitação' END AS Tipo,
    ISNULL(NULLIF(cn.userid, N''), N'-') AS LogAgent,
    o.nome_analista AS NomeAnalista,
    ISNULL(catx.sym, N'N/A') AS Categoria,
    LTRIM(RTRIM(ISNULL(crx.summary, N''))) AS Resumo
FROM #Pop AS o
JOIN #Per AS p ON p.periodo = o.periodo
LEFT JOIN #ContNorm AS cn ON cn.contact_uuid = o.log_agent
OUTER APPLY (
    -- Categoria e Resumo do registro principal do chamado (call_req), so
    -- informativos. TOP (1) por seguranca: ref_num identifica o chamado.
    SELECT TOP (1) cx.summary, cx.category
    FROM dbo.call_req AS cx
    WHERE cx.ref_num = o.sdm
    ORDER BY cx.id
) AS crx
LEFT JOIN dbo.prob_ctg AS catx
    ON catx.persid = crx.category
ORDER BY p.ord, o.abertura_br, o.sdm;
