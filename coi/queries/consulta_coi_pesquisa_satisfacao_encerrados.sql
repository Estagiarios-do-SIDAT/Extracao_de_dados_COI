USE mdb;
SET NOCOUNT ON;

/*
================================================================================
COI - PESQUISA DE SATISFACAO DOS CHAMADOS ENCERRADOS PELO COI
================================================================================

Saida: DOIS result sets.

    Janela 1   StatusSatisfacao, Quantidade
    Janela 2   SDM, RespostaSatisfacao      (a OPCAO selecionada, nao texto livre)

A REGRA DE ENCERRADOS NAO E NOVA

    A populacao vem, LITERALMENTE, da regra ja existente em
    coi/queries/consulta_coi_encerrados.sql - inclusive a validacao do grupo
    alvo. Nenhum criterio de pertencimento ao COI foi criado aqui:

        close_date >= @DataInicio  e  < @DataFim   (semiaberto)
        type       IN ('I','R')
        status     IN ('CL','CLUNRSLV')
        group_id   =  @COI_GrupoAlvo               (UM grupo, nunca dois)
        e o grupo alvo precisa estar ativo e ter ao menos um membro

    O eixo temporal e o close_date, que e o eixo do indicador de Encerrados -
    e NAO o de Registrados (DataRegistroCOI). Sao indicadores diferentes.

    UM grupo por execucao. Somar COI_Antigo + COI_Novo junta dois contratos na
    mesma apuracao. O par (periodo, grupo) vem do contrato auditado e e
    declarado por quem apura, nao inferido dos dados.

O CAMINHO ATE A OPCAO SELECIONADA

    survey             instancia da pesquisa
                       object_type = 'cr' + object_id = call_req.id
      -> survey_question    owning_survey = survey.id
                            sequence = ordem da pergunta
      -> survey_answer      own_srvy_question = survey_question.id
                            txt      = o texto da opcao
                            selected = 1 na opcao ESCOLHIDA

    CUIDADO QUE CUSTOU UMA VERIFICACAO: survey_question.response NAO e o id da
    opcao escolhida. Medido na base inteira, response casa com survey_answer.id
    em ZERO de 208.055 casos. Ele e a SEQUENCE da opcao dentro da pergunta
    (response = 10 -> a opcao de sequence 10). Juntar por response = answer.id
    devolveria vazio silenciosamente.

    O caminho correto e selected = 1, e ele e exato: das 208.055 perguntas
    respondidas, 208.055 tem EXATAMENTE UMA opcao selecionada - nenhuma com
    zero, nenhuma com duas. Nao existe ambiguidade a resolver nesse ponto.

QUAL PERGUNTA VIRA "A" RESPOSTA DE SATISFACAO

    Cada pesquisa tem CINCO perguntas, e portanto cinco opcoes selecionadas. A
    Janela 2 mostra UMA linha por SDM, entao e preciso dizer qual delas e a
    nota. O mapa, por survey_question.sequence:

        10  O problema descrito no chamado foi resolvido?          Sim / Nao
        20  Qualidade do atendimento telefonico / do teleoperador  escala 5 opcoes
        30  Qualidade do atendimento do tecnico presencial         escala 5 opcoes
        40  Satisfacao GERAL com a EXECUCAO DOS SERVICOS           escala 4 opcoes
        50  Satisfacao GERAL com o TEMPO de atendimento            escala 4 opcoes

    PADRAO: sequence 40 - satisfacao geral com a execucao dos servicos. E a
    pergunta de satisfacao mais abrangente, existe em 100% das pesquisas
    (41.612 de 41.612) e usa a escala Otimo / Bom / Regular / Ruim.

    A escolha e um PARAMETRO, nao uma constante enterrada no meio do SQL:
    @SequenciaPerguntaAvaliada. Trocar para 30 devolve a nota do tecnico, para
    50 a do tempo, para 10 o "foi resolvido?".

    A sequence e referencia ESTRUTURAL, nao casamento por texto do enunciado -
    um enunciado reescrito pela area quebraria a consulta em silencio.

CLASSIFICACAO DA JANELA 1

    "Com satisfacao" = a pesquisa do chamado tem ao menos UMA opcao selecionada,
    em qualquer pergunta. E a leitura do enunciado: existe resposta de pesquisa.
    Ela NAO depende da pergunta escolhida para a Janela 2.

    Consequencia declarada: em tese um chamado pode ser "Com satisfacao" e nao
    aparecer na Janela 2, se justo a pergunta avaliada tiver ficado em branco.
    Na base inteira isso ocorre em 1 pesquisa de 41.612 - uma pesquisa criada e
    nunca respondida. O result set de conferencia MEDE essa diferenca em vez de
    supor que ela e zero.

DUPLICIDADE DE PESQUISA

    Na base ha 41.612 pesquisas para 40.660 chamados distintos:

        1 pesquisa .... 39.806 chamados      4 pesquisas ....... 10
        2 pesquisas ....... 775              5 pesquisas ........ 3
        3 pesquisas ........ 65              6 pesquisas ........ 1

    REGRA ADOTADA: fica a MAIS RECENTE, por last_mod_dt decrescente, com
    survey.id decrescente como desempate. Uma reaplicacao de pesquisa substitui
    a anterior. last_mod_dt esta preenchido em 41.612 de 41.612 registros, entao
    o desempate por id nunca e acionado por falta de data.

    NAO se somam respostas de pesquisas diferentes do mesmo SDM: o ROW_NUMBER
    elege uma pesquisa ANTES de qualquer contagem, e o indice UNICO em
    #Satisfacao falha na criacao se essa premissa deixar de valer.

SOMA DA JANELA 1

    Com satisfacao + Sem satisfacao = total de Encerrados COI no periodo, por
    construcao: com_satisfacao e bit, nao admite NULL nem terceiro valor, e o
    LEFT JOIN nao remove chamado sem pesquisa. O result set de conferencia
    recontabiliza o total direto de call_req pela regra oficial e compara.

O COI QUASE NAO RECEBE PESQUISA - ler antes de estranhar um zero

    call_req.z_envia_satisfacao = 0 em TODOS os 30.018 chamados I/R encerrados
    hoje nas filas do COI. A pesquisa nao e disparada para essas filas, e faz
    sentido operacional: o COI e centro de operacoes, seus chamados sao alertas
    de monitoramento e checklists de rotina, sem usuario final a pesquisar.

    Em toda a historia ha 49 chamados hoje em filas do COI com pesquisa - 47 no
    contrato antigo, 2 no novo. As pesquisas vao para as filas de atendimento a
    pessoas: Suporte Local - DF (9.339), Suporte Telefonico (3.751),
    Telessuporte (3.543).

    Entao "Sem satisfacao = total" e o resultado ESPERADO na maioria dos
    periodos, e nao sintoma de consulta quebrada. Periodos com resposta, uteis
    para conferir que o caminho positivo funciona:

        @COI_Novo    01/08/2026 - 01/09/2026     2 respostas
        @COI_Antigo  01/10/2024 - 01/11/2024     2 respostas
        @COI_Antigo  01/05/2023 - 01/06/2023     5 respostas

    Se a intencao for medir satisfacao do atendimento prestado PELO COI, a
    pergunta e de configuracao do SDM - habilitar o envio para essas filas -
    e nao de consulta.

SOMENTE LEITURA. Batch unico, sem GO. 2 result sets (3 com conferencia).
================================================================================
*/

--------------------------------------------------------------------------------
-- [0] PARAMETROS
--------------------------------------------------------------------------------

-- Periodo em horario do Brasil, intervalo SEMIABERTO: >= inicio e < fim.
-- O fim e o PRIMEIRO INSTANTE DE FORA. Nunca usar 23:59:59.
DECLARE @DataInicio datetime2(0) = '2026-03-09 00:00:00';   -- inclusivo
DECLARE @DataFim    datetime2(0) = '2026-04-01 00:00:00';   -- EXCLUSIVO

-- Identidade do COI. SEMPRE por UUID: nome de grupo muda, UUID nao.
DECLARE @COI_Antigo varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;  -- 'Contrato 7/2023 - COI'
DECLARE @COI_Novo   varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;  -- 'COI'

-- GRUPO ALVO: a unica linha que decide QUAL contrato esta sendo apurado.
--     producao / contrato vigente ............... @COI_Novo
--     conferencia do RSP de fevereiro/2026 ...... @COI_Antigo
-- NAO combinar os dois. NAO escolher automaticamente pela data.
DECLARE @COI_GrupoAlvo varbinary(16) = @COI_Novo;

-- Qual pergunta da pesquisa vira a RespostaSatisfacao da Janela 2.
--   10 = O problema foi resolvido?            (Sim / Nao)
--   20 = Atendimento telefonico / teleoperador
--   30 = Atendimento do tecnico presencial
--   40 = Satisfacao GERAL com a execucao dos servicos   <-- padrao
--   50 = Satisfacao GERAL com o tempo de atendimento
DECLARE @SequenciaPerguntaAvaliada int = 40;

-- 1 = acrescenta um terceiro result set que PROVA a soma da Janela 1 contra o
--     total de Encerrados COI e mede a diferenca entre Janela 1 e Janela 2.
DECLARE @MostrarConferencia bit = 1;

-- Conversao para o epoch inteiro em que call_req guarda as datas. Feita UMA
-- vez, em variavel: nenhuma funcao encosta na coluna filtrada, entao close_date
-- continua sargavel.
DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';
DECLARE @IniEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @DataInicio));
DECLARE @FimEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @DataFim));

--------------------------------------------------------------------------------
-- [1] VALIDACAO DO GRUPO ALVO - identica a de consulta_coi_encerrados.sql.
--
-- E o CTE "Fornecedores" da Consulta para Auditoria: o grupo precisa estar
-- ATIVO (inactive = 0) e ter ao menos UM membro em grpmem. A checagem e feita
-- UMA vez sobre o parametro, e nao por linha - grpmem nunca entra no FROM da
-- populacao, entao nao existe caminho para duplicar chamado.
--
-- O PRINT e o antidoto para o zero silencioso: sem ele, um grupo inativo
-- devolveria lista vazia que se parece com "nao houve encerramento no periodo".
--------------------------------------------------------------------------------
DECLARE @GrupoNome    nvarchar(200);
DECLARE @GrupoInativo int;
DECLARE @GrupoMembros bigint;

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
PRINT N'Pergunta ..... sequence ' + CONVERT(nvarchar(10), @SequenciaPerguntaAvaliada);

IF @GrupoAlvoValido = 0
    PRINT N'ATENCAO: o grupo alvo NAO passa no filtro da Consulta para Auditoria '
        + N'(precisa existir, estar com inactive = 0 e ter ao menos um membro em grpmem). '
        + N'O resultado sera VAZIO por causa disso, e nao por ausencia de encerramentos.';

--------------------------------------------------------------------------------
-- [2] POPULACAO - Encerrados pelo COI. A regra inteira mora neste WHERE, e e a
--     mesma de consulta_coi_encerrados.sql, sem acrescimo nem supressao.
--
--     SARGABILIDADE: close_date, status, type e group_id aparecem CRUAS. As
--     conversoes de data ja foram resolvidas em variavel no passo [0].
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#EncerradosCOI') IS NOT NULL DROP TABLE #EncerradosCOI;

SELECT
    r.id,
    r.ref_num AS SDM,
    r.[type]  AS tipo,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.close_date, @Epoch)) AS encerramento_br
INTO #EncerradosCOI
FROM dbo.call_req AS r
WHERE r.close_date >= @IniEpoch
  AND r.close_date <  @FimEpoch
  AND r.[type]   IN ('I', 'R')
  AND r.status   IN ('CL', 'CLUNRSLV')
  AND r.group_id = @COI_GrupoAlvo
  AND @GrupoAlvoValido = 1
OPTION (RECOMPILE);

CREATE UNIQUE CLUSTERED INDEX IX_EncerradosCOI ON #EncerradosCOI(id);

--------------------------------------------------------------------------------
-- [3] UMA pesquisa por chamado: a mais recente.
--
--     O JOIN com a populacao vem ANTES do ROW_NUMBER, entao a janela e
--     calculada so sobre os chamados do periodo - e nao sobre as 41 mil
--     pesquisas da base inteira.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Pesquisa') IS NOT NULL DROP TABLE #Pesquisa;

SELECT z.survey_id, z.call_req_id
INTO #Pesquisa
FROM (
    SELECT s.id AS survey_id, s.object_id AS call_req_id,
           ROW_NUMBER() OVER (PARTITION BY s.object_id
                              ORDER BY s.last_mod_dt DESC, s.id DESC) AS rn
    FROM dbo.survey AS s
    JOIN #EncerradosCOI AS e ON e.id = s.object_id
    WHERE s.object_type = N'cr'
      AND s.del = 0
) AS z
WHERE z.rn = 1;

CREATE UNIQUE CLUSTERED INDEX IX_Pesquisa ON #Pesquisa(call_req_id);

--------------------------------------------------------------------------------
-- [4] O que o usuario selecionou.
--
--     qtd_opcoes_selecionadas  quantas perguntas tiveram opcao escolhida.
--                              Decide "Com satisfacao" na Janela 1.
--     resposta_avaliada        o texto da opcao escolhida NA PERGUNTA ALVO.
--                              Alimenta a Janela 2.
--
--     O TOP (1) em resposta_avaliada e defesa de modelagem, nao expectativa:
--     medido na base, cada pergunta respondida tem exatamente uma opcao com
--     selected = 1. Se um dia tiver duas, a consulta continua devolvendo UMA
--     linha por SDM em vez de duplicar o chamado em silencio.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Satisfacao') IS NOT NULL DROP TABLE #Satisfacao;

SELECT
    p.call_req_id,
    p.survey_id,
    sel.qtd_opcoes_selecionadas,
    CONVERT(nvarchar(200), alvo.txt) AS resposta_avaliada
INTO #Satisfacao
FROM #Pesquisa AS p
CROSS APPLY (
    SELECT qtd_opcoes_selecionadas = COUNT(*)
    FROM dbo.survey_question AS q
    JOIN dbo.survey_answer AS a
        ON a.own_srvy_question = q.id
       AND a.selected = 1
    WHERE q.owning_survey = p.survey_id
) AS sel
OUTER APPLY (
    SELECT TOP (1) a2.txt
    FROM dbo.survey_question AS q2
    JOIN dbo.survey_answer AS a2
        ON a2.own_srvy_question = q2.id
       AND a2.selected = 1
    WHERE q2.owning_survey = p.survey_id
      AND q2.sequence = @SequenciaPerguntaAvaliada
    ORDER BY a2.sequence, a2.id
) AS alvo;

CREATE UNIQUE CLUSTERED INDEX IX_Satisfacao ON #Satisfacao(call_req_id);

--------------------------------------------------------------------------------
-- [5] VEREDICTO por chamado.
--
--     LEFT JOIN: chamado sem pesquisa nenhuma continua na populacao, como "Sem
--     satisfacao". #Satisfacao tem chave unica por call_req_id, entao o join
--     nao multiplica linha - e e por isso que a soma da Janela 1 fecha com o
--     total de Encerrados.
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Resultado') IS NOT NULL DROP TABLE #Resultado;

SELECT
    e.id,
    e.SDM,
    e.tipo,
    e.encerramento_br,
    CONVERT(bit, CASE WHEN ISNULL(s.qtd_opcoes_selecionadas, 0) > 0
                      THEN 1 ELSE 0 END) AS com_satisfacao,
    s.resposta_avaliada
INTO #Resultado
FROM #EncerradosCOI AS e
LEFT JOIN #Satisfacao AS s
    ON s.call_req_id = e.id;

CREATE UNIQUE CLUSTERED INDEX IX_Resultado ON #Resultado(id);

--------------------------------------------------------------------------------
-- JANELA 1 - Resumo da satisfacao
--
--   Uma linha por classificacao. Cada chamado encerrado pelo COI entra em
--   exatamente uma das duas: com_satisfacao e bit, sem NULL e sem terceiro
--   valor.
--------------------------------------------------------------------------------
SELECT
    CONVERT(nvarchar(20), CASE WHEN r.com_satisfacao = 1
                               THEN N'Com satisfação'
                               ELSE N'Sem satisfação' END) AS StatusSatisfacao,
    COUNT(*) AS Quantidade
FROM #Resultado AS r
GROUP BY r.com_satisfacao
ORDER BY r.com_satisfacao DESC;

--------------------------------------------------------------------------------
-- JANELA 2 - Detalhamento das respostas
--
--   Somente chamados com opcao selecionada na pergunta avaliada. Uma linha por
--   SDM, com a opcao escolhida - nao comentario livre.
--------------------------------------------------------------------------------
SELECT
    r.SDM,
    r.resposta_avaliada AS RespostaSatisfacao
FROM #Resultado AS r
WHERE r.resposta_avaliada IS NOT NULL
ORDER BY r.SDM;

--------------------------------------------------------------------------------
-- CONFERENCIA (opcional)
--
--   Prova a soma da Janela 1 contra o total de Encerrados COI, recontado direto
--   de call_req pela regra oficial, e mede a diferenca entre Janela 1 e Janela
--   2 - que so pode existir se a pergunta avaliada tiver ficado em branco numa
--   pesquisa que respondeu as outras.
--------------------------------------------------------------------------------
IF @MostrarConferencia = 1
SELECT
    CONVERT(char(10), @DataInicio, 103) + N' a ' +
        CONVERT(char(10), DATEADD(DAY, -1, @DataFim), 103) AS Periodo,
    ISNULL(@GrupoNome, N'(grupo nao encontrado)')          AS GrupoAlvo,
    @SequenciaPerguntaAvaliada                             AS PerguntaAvaliada,
    o.EncerradosCOI_regraOficial,
    c.TotalNaJanela1,
    c.ComSatisfacao,
    c.SemSatisfacao,
    c.LinhasNaJanela2,
    c.ComSatisfacao - c.LinhasNaJanela2                    AS SemRespostaNaPerguntaAvaliada,
    c.SDMsDistintos,
    CASE WHEN c.TotalNaJanela1 = o.EncerradosCOI_regraOficial
          AND c.TotalNaJanela1 = c.ComSatisfacao + c.SemSatisfacao
          AND c.TotalNaJanela1 = c.SDMsDistintos
         THEN N'SIM' ELSE N'NAO - INVESTIGAR' END          AS SomaFechaComEncerrados
FROM (
    SELECT
        COUNT(*) AS TotalNaJanela1,
        SUM(CASE WHEN r.com_satisfacao = 1 THEN 1 ELSE 0 END) AS ComSatisfacao,
        SUM(CASE WHEN r.com_satisfacao = 0 THEN 1 ELSE 0 END) AS SemSatisfacao,
        SUM(CASE WHEN r.resposta_avaliada IS NOT NULL THEN 1 ELSE 0 END) AS LinhasNaJanela2,
        COUNT(DISTINCT r.SDM) AS SDMsDistintos
    FROM #Resultado AS r
) AS c
CROSS JOIN (
    SELECT COUNT(*) AS EncerradosCOI_regraOficial
    FROM dbo.call_req AS r2
    WHERE r2.close_date >= @IniEpoch
      AND r2.close_date <  @FimEpoch
      AND r2.[type]   IN ('I', 'R')
      AND r2.status   IN ('CL', 'CLUNRSLV')
      AND r2.group_id = @COI_GrupoAlvo
      AND @GrupoAlvoValido = 1
) AS o;
