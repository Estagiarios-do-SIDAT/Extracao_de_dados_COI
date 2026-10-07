USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- VERSAO POWER BI de queries/consulta_coi_registrados_total_com_tecnicos.sql
--
-- A regra e a da consulta de /queries, que e a fonte de verdade. Este arquivo
-- e o texto dela sem alteracao, exceto pelas adaptacoes abaixo, marcadas no
-- corpo com [POWER BI]. Se esta versao e a fonte divergirem, vale a fonte.
--
-- Adaptacoes:
--   - periodo NAO automatizado: a fonte trabalha com periodos de conferencia
--     fixos, amarrados a um roster de analistas transcrito dos relatorios do
--     fornecedor para cada um deles. Um periodo automatico nao teria roster e
--     mudaria o resultado. Os periodos sao os da fonte;
--   - saida unica: a fonte devolve varios result sets, e o Power BI le apenas o
--     primeiro. Cada result set e gravado em #PBI_Saida, com as colunas e a
--     ordem de linhas da fonte, e todos saem num unico resultado, discriminado
--     por [TipoResultado]. Colunas que nao pertencem ao result set da linha vem
--     NULL; colunas de mesmo nome em mais de um result set sao a mesma coluna.
--     Colunas de texto saem como nvarchar, com os mesmos valores.
--
-- Valores de [TipoResultado], na ordem em que a fonte os devolve:
--     RESUMO_PERIODO       RS 1 - resumo por periodo
--     ORIGEM_DO_TOTAL      RS 2 - origem de cada chamado do total
--     DETALHE              RS 3 - detalhe por SDM
--
-- Power BI: conector SQL Server, banco mdb, modo Importacao, este arquivo
-- inteiro no campo Instrucao SQL, Adicionar colunas de relacao desmarcado.
-- Somente leitura. Batch unico, sem GO.
--------------------------------------------------------------------------------


/*
================================================================================
COI - REGISTRADOS: TOTAL COI = MEMBROS + TECNICOS COM ORIGEM COI COMPROVADA
================================================================================

O QUE ESTA CONSULTA ENTREGA

    A populacao de Registrados do COI que se consegue DEMONSTRAR:

        MEMBRO_COI
        + TECNICO_COI_ORIGEM_CONFIRMADA_INIT
        + TECNICO_COI_ORIGEM_CONFIRMADA_HISTORICO

    Uma linha por SDM, sem sobreposicao entre as tres origens.

POR QUE AS CONTAS TECNICAS PRECISAM PROVAR ORIGEM

    ServiceDesk, usr_automacoes e sesuc_auto NAO sao do COI. Sao contas
    compartilhadas, usadas tambem por NSTI REDE, NSTI SO, NSTI BD e outros
    nucleos. Contar tudo que sai delas seria atribuir ao COI servico alheio.

    Por isso a regra e assimetrica de proposito:

        membro humano  -> basta estar no roster historico do periodo
        conta tecnica  -> precisa de evidencia de que o chamado nasceu no COI

HIERARQUIA DA EVIDENCIA

        1  %GROUP= do evento INIT      declaracao no ato da criacao
        2  primeiro grupo historico    origem do 1o evento de mudanca de grupo
        3  sem evidencia               FICA DE FORA

    group_id ATUAL nao e usado em nenhum ramo. O grupo de hoje diz onde o chamado
    esta, nao onde nasceu - e ja foi medido que resolver nome historico contra o
    cadastro atual reescreve o passado.

O QUE ESTA CONSULTA NAO E

    Ela nao reproduz o total historico do RSP antigo, e nao tenta. O universo
    alto (~3 mil) esta preservado, com cada linha classificada, em:

        coi/queries/consulta_coi_registrados_universo_bruto.sql

    A diferenca entre os dois numeros nao e erro: e a parte da volumetria que se
    apoiava em conta compartilhada sem prova de origem.

REFERENCIA DE VALIDACAO (medida, nao codificada em predicado)

        FEV  I=462  R=732  Total=1194
        MAR  I=612  R=809  Total=1421
        JUN  I=479  R=729  Total=1208

SOMENTE LEITURA. Batch unico, sem GO. 3 result sets.
================================================================================
*/

--------------------------------------------------------------------------------
-- INICIO REGRA COMPARTILHADA TECNICOS COI
--
-- Tudo entre este marcador e o FIM e IDENTICO, byte a byte, em:
--
--     consulta_coi_registrados_total_com_tecnicos.sql
--     consulta_coi_registrados_universo_bruto.sql
--
-- As duas consultas respondem perguntas diferentes sobre a MESMA classificacao.
-- Se este bloco divergir entre elas, os dois numeros passam a nao ser
-- comparaveis e o universo bruto deixa de ser auditoria do total. Conferir com:
--
--     recortar o trecho entre os marcadores nos dois arquivos e comparar SHA256.
--
-- Para trocar o periodo, edite SOMENTE o bloco [0.1] - ele e parametro, nao
-- regra, e por isso fica dentro do bloco compartilhado de proposito: os dois
-- arquivos precisam olhar exatamente a mesma janela.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- [0.1] PARAMETROS - PERIODOS. EDITE AQUI.
--
-- Os tres periodos abaixo sao os de validacao. MARCO E 09/03 A 31/03: e o
-- intervalo que o RSP daquele mes cobre, e nao o mes cheio. Fim SEMPRE
-- exclusivo.
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
-- [0.2] IDENTIDADE DO COI - duas listas curtas e fechadas.
--
-- #CoiInit  valores de %GROUP= aceitos como COI na criacao.
-- #Alias    nomes historicos aceitos como COI no evento de mudanca de grupo.
--
-- NAO entram, e cada um por um motivo diferente:
--     10-COI      ambiguo; nunca foi provado equivalente ao COI.
--     COI_NOVO    e o nome ATUAL do grupo, nao um valor de origem historica.
--     NSTI *      outros nucleos.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#CoiInit') IS NOT NULL DROP TABLE #CoiInit;
CREATE TABLE #CoiInit (valor_norm nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
INSERT INTO #CoiInit (valor_norm) VALUES (N'COI'), (N'CONTRATO 7/2023 - COI');

IF OBJECT_ID('tempdb..#Alias') IS NOT NULL DROP TABLE #Alias;
CREATE TABLE #Alias (nome_norm nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
INSERT INTO #Alias (nome_norm) VALUES (N'COI'), (N'CONTRATO 7/2023 - COI');

--------------------------------------------------------------------------------
-- [1] ROSTER HISTORICO POR PERIODO.
--
-- Extraido da tabela por analista (DADOS!M:P) do RSP de cada mes. E o quadro
-- daquele periodo, nao o de hoje: dbo.grpmem guarda a composicao ATUAL e usa-lo
-- aqui trocaria a equipe do mes pela equipe atual. A equipe mudou entre estes
-- meses, entao a diferenca nao seria pequena.
--
-- s_rsp e i_rsp sao o que o RSP publica para o analista. Sao REFERENCIA de
-- conferencia: nenhum predicado deste arquivo os utiliza.
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
-- [2] CONTATOS NORMALIZADOS, ROSTER RESOLVIDO E AS TRES CONTAS TECNICAS.
--
-- A normalizacao de nome e a ja validada no projeto: UPPER, pontuacao virando
-- espaco, espacos colapsados, particulas DE/DA/DO/DAS/DOS removidas e JR
-- canonizado para JUNIOR, com acento resolvido por COLLATE Latin1_General_CI_AI.
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

-- Um contato resolve para UM nome por periodo. A chave unica e o que garante
-- que o JOIN adiante nao multiplique chamado.
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

-- As tres contas compartilhadas. Elas NAO sao do COI: sao usadas tambem por
-- outros nucleos, e por isso o nome da conta nunca basta para atribuir o
-- chamado. Quem decide e a origem, apurada no bloco [5].
IF OBJECT_ID('tempdb..#Tec') IS NOT NULL DROP TABLE #Tec;
SELECT t.contact_uuid, CONVERT(varchar(20), t.conta) COLLATE DATABASE_DEFAULT AS conta
INTO #Tec
FROM (
    SELECT c.contact_uuid, 'usr_automacoes' AS conta FROM #ContNorm AS c
    WHERE c.userid COLLATE Latin1_General_CI_AI = N'USR_AUTOMACOES'
    UNION
    SELECT c.contact_uuid, 'sesuc_auto' FROM #ContNorm AS c
    WHERE c.userid COLLATE Latin1_General_CI_AI = N'SESUC_AUTO'
    UNION
    SELECT c.contact_uuid, 'ServiceDesk' FROM #ContNorm AS c
    WHERE c.userid   COLLATE Latin1_General_CI_AI LIKE N'%SERVICEDESK%'
       OR c.n_basico COLLATE Latin1_General_CI_AI LIKE N'%SERVICEDESK%'
       OR c.n_basico COLLATE Latin1_General_CI_AI LIKE N'%SERVICE DESK%'
) AS t;
CREATE UNIQUE CLUSTERED INDEX IX_Tec ON #Tec(contact_uuid);

--------------------------------------------------------------------------------
-- [3] UNIVERSO - I/R abertos na janela, registrados por membro do roster OU por
--     uma das tres contas tecnicas. Uma linha por SDM.
--
-- Sem filtro de grupo, status, prioridade, SLA, customer ou canal.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Inc') IS NOT NULL DROP TABLE #Inc;

SELECT
    r.id, r.persid, r.ref_num AS sdm, r.[type] AS tipo, r.log_agent, r.group_id,
    DATEADD(HOUR, -@H, DATEADD(SECOND, r.open_date, @Epoch)) AS abertura_br,
    pe.periodo, pe.ano, pe.mes,
    CONVERT(bit, CASE WHEN ru.contact_uuid IS NOT NULL THEN 1 ELSE 0 END) AS eh_roster,
    CONVERT(nvarchar(120), ru.nome) COLLATE DATABASE_DEFAULT AS nome_roster,
    CONVERT(varchar(20), ISNULL(tc.conta, '')) COLLATE DATABASE_DEFAULT AS conta_tec
INTO #Inc
FROM dbo.call_req AS r
CROSS APPLY (
    SELECT TOP (1) p.periodo, p.ano, p.mes
    FROM #Per AS p
    WHERE r.open_date >= p.ini_e AND r.open_date < p.fim_e
    ORDER BY p.ord
) AS pe
LEFT JOIN #RosterUuid AS ru ON ru.periodo = pe.periodo AND ru.contact_uuid = r.log_agent
LEFT JOIN #Tec        AS tc ON tc.contact_uuid = r.log_agent
WHERE r.[type] IN ('I', 'R')
  AND r.open_date >= @MinE
  AND r.open_date <  @MaxE
  AND (ru.contact_uuid IS NOT NULL OR tc.contact_uuid IS NOT NULL)
OPTION (RECOMPILE);

CREATE UNIQUE CLUSTERED INDEX IX_Inc ON #Inc(id);

-- act_log so precisa ser lido para as contas tecnicas: membro humano nao
-- depende de origem para entrar. Isto reduz a leitura a uma fracao do universo.
IF OBJECT_ID('tempdb..#IncTec') IS NOT NULL DROP TABLE #IncTec;
SELECT i.id, i.persid
INTO #IncTec
FROM #Inc AS i
WHERE i.eh_roster = 0 AND i.conta_tec <> '';
CREATE UNIQUE CLUSTERED INDEX IX_IncTec ON #IncTec(id);
CREATE INDEX IX_IncTec_persid ON #IncTec(persid);

--------------------------------------------------------------------------------
-- [4] ACT_LOG - leitura UNICA, somente dos chamados tecnicos.
--
-- O join usa al.call_req_id = t.persid CRU. act_log_x0 e NONCLUSTERED sobre
-- call_req_id: qualquer CAST, CONVERT ou COLLATE sobre essa coluna destroi o
-- seek e transforma a consulta em varredura de ~20,9 milhoes de linhas.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Atos') IS NOT NULL DROP TABLE #Atos;
SELECT
    t.id, al.system_time,
    CONVERT(varchar(30), al.[type]) COLLATE DATABASE_DEFAULT AS tipo_ato,
    (CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' ' +
     CONVERT(nvarchar(max), ISNULL(al.action_desc, N''))) COLLATE DATABASE_DEFAULT AS texto
INTO #Atos
FROM #IncTec AS t
JOIN dbo.act_log AS al ON al.call_req_id = t.persid
WHERE al.system_time IS NOT NULL
OPTION (RECOMPILE);
CREATE CLUSTERED INDEX IX_Atos ON #Atos(id, system_time);

--------------------------------------------------------------------------------
-- [5] EVIDENCIA 1 - %GROUP= NO EVENTO INIT.
--
-- O INIT do ServiceDesk carrega a mensagem de criacao, e nela vem o grupo
-- pedido na propria abertura:
--
--     Criado via interface CMD. Mensagem de origem: ... %GROUP=COI ...
--
-- Isso e declaracao explicita no ato da criacao - melhor que group_id atual, que
-- e o estado de hoje, e melhor que o primeiro evento de transferencia, que so
-- existe se houve transferencia.
--
-- O valor comeca logo depois do '=' e termina no proximo '%'; se nao houver
-- outro '%', vai ate o fim do texto. A busca e pelo literal '%GROUP=', entao
-- '%CATEGORY=COI...' nunca e lido como grupo e '%SUBGROUP=' tambem nao casa.
-- DATALENGTH/2 em vez de LEN porque LEN descarta espacos a direita e erraria o
-- comprimento no caso sem '%' final.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#GrpTag') IS NOT NULL DROP TABLE #GrpTag;
SELECT
    a.id, a.system_time,
    CONVERT(nvarchar(200), v.bruto) COLLATE DATABASE_DEFAULT AS valor_bruto,
    CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(
        UPPER(REPLACE(REPLACE(REPLACE(v.bruto, CHAR(13), N' '), CHAR(10), N' '), CHAR(9), N' ')),
        N' ', N'<>'), N'><', N''), N'<>', N' '))))
        COLLATE DATABASE_DEFAULT AS valor_norm
INTO #GrpTag
FROM #Atos AS a
CROSS APPLY (SELECT p = CHARINDEX(N'%GROUP=', a.texto COLLATE Latin1_General_CI_AI)) AS t
CROSS APPLY (SELECT ini = t.p + 7) AS s
CROSS APPLY (SELECT fim = CASE WHEN t.p > 0 THEN CHARINDEX(N'%', a.texto, s.ini) ELSE 0 END) AS e
CROSS APPLY (SELECT tam = CASE WHEN t.p = 0 THEN 0
                               WHEN e.fim > s.ini THEN e.fim - s.ini
                               ELSE (DATALENGTH(a.texto) / 2) - s.ini + 1 END) AS n
CROSS APPLY (SELECT bruto = CASE WHEN n.tam > 0
                                 THEN LTRIM(RTRIM(SUBSTRING(a.texto, s.ini, n.tam))) ELSE N'' END) AS v
WHERE a.tipo_ato = 'INIT'
  AND t.p > 0 AND n.tam > 0 AND LEN(LTRIM(RTRIM(v.bruto))) > 0;
CREATE CLUSTERED INDEX IX_GrpTag ON #GrpTag(id, system_time);

IF OBJECT_ID('tempdb..#InitG') IS NOT NULL DROP TABLE #InitG;
SELECT z.id, z.valor_bruto, z.valor_norm
INTO #InitG
FROM (
    SELECT g.id, g.valor_bruto, g.valor_norm,
           rn = ROW_NUMBER() OVER (PARTITION BY g.id ORDER BY g.system_time)
    FROM #GrpTag AS g
) AS z
WHERE z.rn = 1;
CREATE UNIQUE CLUSTERED INDEX IX_InitG ON #InitG(id);

--------------------------------------------------------------------------------
-- [6] EVIDENCIA 2 - MUDANCA REAL DE GRUPO.
--
-- Somente as cinco ancoras confirmadas semanticamente. Uma rodada anterior usou
-- uma rede ampla (TRANSFER / ATRIBU / ASSIGN) e ela contaminou o resultado com
--
--     Transferir Responsável de 'A' para 'B'
--
-- que e troca de ANALISTA, nao de grupo. Nenhuma das ancoras abaixo casa com
-- esse texto, e e por isso que elas sao literais e nao um padrao generico.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#GrpRaw') IS NOT NULL DROP TABLE #GrpRaw;
SELECT a.id, a.system_time,
       CONVERT(nvarchar(400), SUBSTRING(a.texto, anc.posicao, 400)) COLLATE DATABASE_DEFAULT AS resto
INTO #GrpRaw
FROM #Atos AS a
CROSS APPLY (SELECT p1 = CHARINDEX(N'Grupo de', a.texto), p2 = CHARINDEX(N'Grupo alterado de', a.texto),
                    p3 = CHARINDEX(N'Grupo transferido de', a.texto), p4 = CHARINDEX(N'Group from', a.texto),
                    p5 = CHARINDEX(N'Group changed from', a.texto)) AS pos
CROSS APPLY (SELECT posicao = CASE
        WHEN pos.p1 > 0 THEN pos.p1 + LEN(N'Grupo de')
        WHEN pos.p2 > 0 THEN pos.p2 + LEN(N'Grupo alterado de')
        WHEN pos.p3 > 0 THEN pos.p3 + LEN(N'Grupo transferido de')
        WHEN pos.p4 > 0 THEN pos.p4 + LEN(N'Group from')
        WHEN pos.p5 > 0 THEN pos.p5 + LEN(N'Group changed from')
        ELSE 0 END) AS anc
WHERE anc.posicao > 0;

IF OBJECT_ID('tempdb..#GrpEv') IS NOT NULL DROP TABLE #GrpEv;
SELECT g.id, g.system_time AS evento,
    CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(
        UPPER(LTRIM(RTRIM(ori.nome))), N' ', N'<>'), N'><', N''), N'<>', N' '))))
        COLLATE DATABASE_DEFAULT AS origem_norm
INTO #GrpEv
FROM #GrpRaw AS g
CROSS APPLY (SELECT q1 = CHARINDEX(N'''', g.resto)) AS c1
CROSS APPLY (SELECT q2 = CASE WHEN c1.q1 > 0 THEN CHARINDEX(N'''', g.resto, c1.q1 + 1) ELSE 0 END) AS c2
CROSS APPLY (SELECT nome = CASE WHEN c2.q2 > c1.q1
                                THEN SUBSTRING(g.resto, c1.q1 + 1, c2.q2 - c1.q1 - 1) ELSE N'' END) AS ori
WHERE c1.q1 > 0 AND c2.q2 > c1.q1 AND LEN(LTRIM(RTRIM(ori.nome))) > 0;
CREATE CLUSTERED INDEX IX_GrpEv ON #GrpEv(id, evento);

-- PRIMEIRO grupo historico conhecido = origem do primeiro evento de mudanca.
-- E ORIGEM, nao passagem: um chamado criado por outro nucleo e transferido
-- depois ao COI passou pelo COI, mas nasceu fora dele.
IF OBJECT_ID('tempdb..#Hist') IS NOT NULL DROP TABLE #Hist;
SELECT t.id, pe.origem_norm
INTO #Hist
FROM #IncTec AS t
CROSS APPLY (
    SELECT TOP (1) e.origem_norm
    FROM #GrpEv AS e WHERE e.id = t.id
    ORDER BY e.evento, e.origem_norm
) AS pe;
CREATE UNIQUE CLUSTERED INDEX IX_Hist ON #Hist(id);

--------------------------------------------------------------------------------
-- [7] CLASSIFICACAO - exatamente UMA por SDM.
--
--     MEMBRO_COI                               log_agent no roster do periodo
--     TECNICO_COI_ORIGEM_CONFIRMADA_INIT       %GROUP= do INIT e alias do COI
--     TECNICO_COI_ORIGEM_CONFIRMADA_HISTORICO  1o grupo historico e alias do COI
--     TECNICO_ORIGEM_OUTRO_NUCLEO_INIT         %GROUP= aponta outro nucleo
--     TECNICO_ORIGEM_OUTRO_NUCLEO_HISTORICO    1o grupo historico e outro nucleo
--     TECNICO_ORIGEM_NAO_COMPROVADA            nenhuma das duas evidencias
--
-- INIT tem prioridade sobre historico: e declaracao no ato da criacao, e o
-- historico so registra o que mudou depois. group_id ATUAL nao entra em
-- nenhum ramo - o grupo de hoje nao diz onde o chamado nasceu.
--
-- Como isto e um CASE unico sobre uma tabela de chave unica, um SDM nao pode
-- receber duas classificacoes nem ser contado duas vezes.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Cls') IS NOT NULL DROP TABLE #Cls;
SELECT
    i.id, i.sdm, i.tipo, i.periodo, i.ano, i.mes, i.log_agent, i.group_id,
    i.abertura_br, i.conta_tec, i.eh_roster, i.nome_roster,
    CONVERT(nvarchar(200), ISNULL(ig.valor_norm, N'')) COLLATE DATABASE_DEFAULT AS grupo_init,
    CONVERT(nvarchar(200), ISNULL(h.origem_norm, N'')) COLLATE DATABASE_DEFAULT AS grupo_hist,
    CONVERT(varchar(16), f.fonte) COLLATE DATABASE_DEFAULT AS fonte_evidencia,
    CONVERT(varchar(42), k.classe) COLLATE DATABASE_DEFAULT AS classificacao,
    CONVERT(bit, CASE WHEN k.classe IN ('MEMBRO_COI',
                                        'TECNICO_COI_ORIGEM_CONFIRMADA_INIT',
                                        'TECNICO_COI_ORIGEM_CONFIRMADA_HISTORICO')
                      THEN 1 ELSE 0 END) AS no_total_coi,
    CONVERT(nvarchar(200), CASE
        WHEN i.eh_roster = 1 THEN N'(membro do roster)'
        WHEN ig.id IS NOT NULL THEN ig.valor_norm
        WHEN h.id  IS NOT NULL THEN h.origem_norm
        ELSE N'(sem evidencia)' END) COLLATE DATABASE_DEFAULT AS grupo_origem
INTO #Cls
FROM #Inc AS i
LEFT JOIN #InitG AS ig ON ig.id = i.id
LEFT JOIN #Hist  AS h  ON h.id  = i.id
LEFT JOIN #CoiInit AS ci ON ci.valor_norm COLLATE Latin1_General_CI_AI
                          = ig.valor_norm COLLATE Latin1_General_CI_AI
LEFT JOIN #Alias   AS al ON al.nome_norm  COLLATE Latin1_General_CI_AI
                          = h.origem_norm COLLATE Latin1_General_CI_AI
CROSS APPLY (SELECT fonte = CASE
    WHEN i.eh_roster = 1   THEN 'ROSTER'
    WHEN ig.id IS NOT NULL THEN 'INIT_GROUP'
    WHEN h.id  IS NOT NULL THEN 'HISTORICO_GRUPO'
    ELSE 'SEM_EVIDENCIA' END) AS f
CROSS APPLY (SELECT classe = CASE
    WHEN i.eh_roster = 1 THEN 'MEMBRO_COI'
    WHEN ig.id IS NOT NULL AND ci.valor_norm IS NOT NULL THEN 'TECNICO_COI_ORIGEM_CONFIRMADA_INIT'
    WHEN ig.id IS NOT NULL THEN 'TECNICO_ORIGEM_OUTRO_NUCLEO_INIT'
    WHEN h.id IS NOT NULL AND al.nome_norm IS NOT NULL THEN 'TECNICO_COI_ORIGEM_CONFIRMADA_HISTORICO'
    WHEN h.id IS NOT NULL THEN 'TECNICO_ORIGEM_OUTRO_NUCLEO_HISTORICO'
    ELSE 'TECNICO_ORIGEM_NAO_COMPROVADA' END) AS k;
CREATE UNIQUE CLUSTERED INDEX IX_Cls ON #Cls(id);

--------------------------------------------------------------------------------
-- FIM REGRA COMPARTILHADA TECNICOS COI
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- [POWER BI] SAIDA UNICA
--
-- Cada result set da fonte e gravado aqui, na ordem de linhas dela. O
-- resultado unico sai no fim do arquivo.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PBI_Saida') IS NOT NULL DROP TABLE #PBI_Saida;
CREATE TABLE #PBI_Saida (
    PBI_Ordem                     int IDENTITY(1, 1) NOT NULL PRIMARY KEY,
    TipoResultado                 varchar(30) NOT NULL,
    [Periodo]                     nvarchar(3) NULL,
    [Ano]                         int NULL,
    [Mes]                         int NULL,
    [Incidentes]                  int NULL,
    [Solicitacoes]                int NULL,
    [Total]                       int NULL,
    [SDMsDistintos]               int NULL,
    [Duplicados]                  int NULL,
    [TecnicosSemOrigem_foraDoTotal] int NULL,
    [OrigemPopulacao]             nvarchar(42) NULL,
    [SDM]                         nvarchar(30) NULL,
    [Tipo]                        nvarchar(11) NULL,
    [DataAbertura]                datetime2(0) NULL,
    [LogAgent]                    nvarchar(120) NULL,
    [NomeLogAgent]                nvarchar(120) NULL,
    [FonteEvidenciaOrigem]        nvarchar(16) NULL,
    [GrupoOrigem]                 nvarchar(200) NULL,
    [GrupoAtual_soReferencia]     nvarchar(120) NULL,
    [AnalistaDoRoster]            nvarchar(120) NULL
);

--------------------------------------------------------------------------------
-- RS 1 - RESUMO POR PERIODO.
--        Linhas x SDMsDistintos e a assercao de que as tres origens nao se
--        sobrepoem; Duplicados tem de ser 0.
--------------------------------------------------------------------------------
-- [POWER BI] grava este result set em #PBI_Saida.
INSERT INTO #PBI_Saida (TipoResultado, [Periodo], [Ano], [Mes], [Incidentes], [Solicitacoes], [Total], [SDMsDistintos], [Duplicados], [TecnicosSemOrigem_foraDoTotal])
SELECT
    'RESUMO_PERIODO',
    p.periodo AS Periodo,
    p.ano AS Ano,
    p.mes AS Mes,
    SUM(CASE WHEN c.no_total_coi = 1 AND c.tipo = 'I' THEN 1 ELSE 0 END) AS Incidentes,
    SUM(CASE WHEN c.no_total_coi = 1 AND c.tipo = 'R' THEN 1 ELSE 0 END) AS Solicitacoes,
    SUM(CASE WHEN c.no_total_coi = 1 THEN 1 ELSE 0 END) AS Total,
    COUNT(DISTINCT CASE WHEN c.no_total_coi = 1 THEN c.sdm END) AS SDMsDistintos,
    SUM(CASE WHEN c.no_total_coi = 1 THEN 1 ELSE 0 END)
        - COUNT(DISTINCT CASE WHEN c.no_total_coi = 1 THEN c.sdm END) AS Duplicados,
    SUM(CASE WHEN c.classificacao = 'TECNICO_ORIGEM_NAO_COMPROVADA' THEN 1 ELSE 0 END)
        AS TecnicosSemOrigem_foraDoTotal
FROM #Per AS p
LEFT JOIN #Cls AS c ON c.periodo = p.periodo
GROUP BY p.ord, p.periodo, p.ano, p.mes
ORDER BY p.ord;

--------------------------------------------------------------------------------
-- RS 2 - DE ONDE VEM CADA CHAMADO DO TOTAL
--------------------------------------------------------------------------------
-- [POWER BI] grava este result set em #PBI_Saida.
INSERT INTO #PBI_Saida (TipoResultado, [Periodo], [Ano], [Mes], [OrigemPopulacao], [Incidentes], [Solicitacoes], [Total])
SELECT
    'ORIGEM_DO_TOTAL',
    p.periodo AS Periodo,
    p.ano AS Ano,
    p.mes AS Mes,
    o.rot AS OrigemPopulacao,
    ISNULL(q.i, 0) AS Incidentes,
    ISNULL(q.r, 0) AS Solicitacoes,
    ISNULL(q.t, 0) AS Total
FROM #Per AS p
CROSS JOIN (VALUES
    (1, CONVERT(nvarchar(30), N'MEMBRO_COI'),
        CONVERT(varchar(42), 'MEMBRO_COI')),
    (2, N'TECNICO_COI_INIT',      'TECNICO_COI_ORIGEM_CONFIRMADA_INIT'),
    (3, N'TECNICO_COI_HISTORICO', 'TECNICO_COI_ORIGEM_CONFIRMADA_HISTORICO')
) AS o(ord, rot, classe)
OUTER APPLY (
    SELECT i = SUM(CASE WHEN c.tipo = 'I' THEN 1 ELSE 0 END),
           r = SUM(CASE WHEN c.tipo = 'R' THEN 1 ELSE 0 END),
           t = COUNT(*)
    FROM #Cls AS c
    WHERE c.periodo = p.periodo AND c.classificacao = o.classe
) AS q
ORDER BY p.ord, o.ord;

--------------------------------------------------------------------------------
-- RS 3 - DETALHE AUDITAVEL, uma linha por SDM.
--
-- GrupoAtual_soReferencia esta aqui para conferencia humana e nao participa de
-- nenhum predicado. O nome da coluna diz isso a quem ler o resultado sem ler
-- este cabecalho.
--------------------------------------------------------------------------------
-- [POWER BI] grava este result set em #PBI_Saida.
INSERT INTO #PBI_Saida (TipoResultado, [Periodo], [SDM], [Tipo], [DataAbertura], [LogAgent], [NomeLogAgent], [OrigemPopulacao], [FonteEvidenciaOrigem], [GrupoOrigem], [GrupoAtual_soReferencia], [AnalistaDoRoster])
SELECT
    'DETALHE',
    c.periodo AS Periodo,
    c.sdm AS SDM,
    CASE c.tipo WHEN 'I' THEN N'Incidente' ELSE N'Solicitação' END AS Tipo,
    c.abertura_br AS DataAbertura,
    ISNULL(NULLIF(cn.userid, N''), N'-') AS LogAgent,
    CASE WHEN c.log_agent IS NULL THEN N'(sem registrador)'
         WHEN cn.contact_uuid IS NULL THEN N'(UUID sem contato)'
         ELSE ISNULL(NULLIF(cn.nome_bruto, N''), N'(contato sem nome)') END AS NomeLogAgent,
    c.classificacao AS OrigemPopulacao,
    c.fonte_evidencia AS FonteEvidenciaOrigem,
    c.grupo_origem AS GrupoOrigem,
    ISNULL(NULLIF(cg.nome_bruto, N''), N'(grupo nao resolvido)') AS GrupoAtual_soReferencia,
    ISNULL(c.nome_roster, N'-') AS AnalistaDoRoster
FROM #Cls AS c
JOIN #Per AS p ON p.periodo = c.periodo
LEFT JOIN #ContNorm AS cn ON cn.contact_uuid = c.log_agent
LEFT JOIN #ContNorm AS cg ON cg.contact_uuid = c.group_id
WHERE c.no_total_coi = 1
ORDER BY p.ord, c.abertura_br, c.sdm;

--------------------------------------------------------------------------------
-- [POWER BI] RESULTADO UNICO
--------------------------------------------------------------------------------
SELECT
    TipoResultado,
    [Periodo],
    [Ano],
    [Mes],
    [Incidentes],
    [Solicitacoes],
    [Total],
    [SDMsDistintos],
    [Duplicados],
    [TecnicosSemOrigem_foraDoTotal],
    [OrigemPopulacao],
    [SDM],
    [Tipo],
    [DataAbertura],
    [LogAgent],
    [NomeLogAgent],
    [FonteEvidenciaOrigem],
    [GrupoOrigem],
    [GrupoAtual_soReferencia],
    [AnalistaDoRoster]
FROM #PBI_Saida
ORDER BY PBI_Ordem;
