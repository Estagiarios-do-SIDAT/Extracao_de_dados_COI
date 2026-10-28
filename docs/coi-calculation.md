# Como o COI é calculado

Este documento explica as regras de cálculo do COI: quem conta como
**Registrado**, quem conta como **Encerrado**, de onde vem cada data e como cada
consulta agrupa o resultado. É para quem precisa **entender e conferir os
números**.

As regras aqui descritas são as das consultas de `queries/`, que são a
referência funcional do COI.

---

## Índice

1. [O que as consultas fazem](#1-o-que-as-consultas-fazem)
2. [Fonte dos dados](#2-fonte-dos-dados)
3. [Chamados Registrados](#3-chamados-registrados)
4. [`DataRegistroCOI`](#4-dataregistrocoi)
5. [Automações](#5-automações)
6. [Chamados Encerrados](#6-chamados-encerrados)
7. [Registrados × Encerrados por dia](#7-registrados--encerrados-por-dia)
8. [Registrados por mês](#8-registrados-por-mês)
9. [Por hora](#9-por-hora)
10. [Registrados por evidência e detalhe](#10-registrados-por-evidência-e-detalhe)
11. [Por registrador e por membro](#11-por-registrador-e-por-membro)
12. [Membros, contas técnicas e universo bruto](#12-membros-contas-técnicas-e-universo-bruto)
13. [Validação](#13-validação)
14. [Pesquisa de satisfação dos Encerrados](#14-pesquisa-de-satisfação-dos-encerrados)
15. [Parâmetros](#15-parâmetros)
16. [Limitações](#16-limitações)

---

## 1. O que as consultas fazem

O COI não tem FAIA nem FARC. O que se mede é **volumetria**: quantos chamados
entram no COI, quantos o COI encerra e em que horário os registros acontecem.

São dezesseis consultas, em três famílias:

| Família | Consultas | Regra |
|---|---|---|
| **Registrados** | `mensal`, `encerrados_diario`, `por_hora`, `detalhe`, `por_registrador`, `por_evidencia`, `validacao` e as séries de registrados de `registrados_encerrados_por_membro` e `registrados_encerrados_por_hora` | Primeira entrada do chamado no COI — seções [3](#3-chamados-registrados) a [5](#5-automações) |
| **Encerrados** | `consulta_coi_encerrados.sql`, `encerrados_por_hora`, `pesquisa_satisfacao_encerrados`, `pesquisa_satisfacao_encerrados_detalhe` e as séries de encerrados do diário, do por membro e do por hora | Fechamento no grupo auditado — seção [6](#6-chamados-encerrados) |
| **Conciliação por abertura** | `membros`, `total_com_tecnicos`, `universo_bruto` | Chamados abertos por analistas do COI e por contas técnicas — seção [12](#12-membros-contas-técnicas-e-universo-bruto) |

As nove consultas que contam Registrados aplicam **a mesma regra**, com o mesmo
texto: as sete originais e as de Registrados × Encerrados por membro e por hora. O que muda
entre elas é só a forma de agrupar e apresentar o resultado. Por isso os totais
de uma batem com os das outras para o mesmo período. Da mesma forma, as
consultas de Encerrados copiam literalmente a regra e a conferência do grupo
alvo de `consulta_coi_encerrados.sql`.

Seis delas alimentam o painel do Power BI; quais são, e por que as demais ficam
só em `queries/`, está em `powerbi/powerbi-query.md`.

Registrado e Encerrado são **indicadores diferentes**, com regras e datas
diferentes.

---

## 2. Fonte dos dados

Base `mdb` do CA Service Desk Manager, lida somente para leitura.

| Tabela | Papel |
|---|---|
| `call_req` | O chamado: número (SDM), tipo, status, grupo atual, abertura, fechamento, resolução e quem o abriu |
| `act_log` | Histórico de eventos. As transferências de grupo (eventos `TR`), o registro de criação (evento `INIT`), os eventos de fechamento e de solução (quem encerrou, seção [11](#11-por-registrador-e-por-membro)) e o pedido de pesquisa (`SRVY_SENT`, seção [14](#14-pesquisa-de-satisfação-dos-encerrados)) |
| `ca_contact` | Cadastro de grupos e pessoas: identifica a fila do COI, as contas técnicas e os nomes |
| `grpmem` | Composição dos grupos: confere se o grupo auditado em Encerrados tem membros e classifica as contas como membro do COI |
| `cr_stat`, `prob_ctg`, `ca_owned_resource` | Nome do status, categoria e item de configuração, na listagem de Encerrados |
| `survey`, `survey_question`, `survey_answer` | Pesquisa de satisfação: a pesquisa, as perguntas e a opção escolhida |
| `sys.all_objects` | Catálogo do SQL Server, usado só para gerar a sequência de dias e horas dos calendários |

Datas em `call_req` e `act_log` são gravadas em segundos, em UTC. As consultas
as convertem para o **horário de Brasília (UTC−3)**, e todo período é informado e
exibido nesse horário.

---

## 3. Chamados Registrados

**Registrado pelo COI** é o chamado que **entra no COI pela primeira vez na sua
vida**. Cada chamado produz uma única data, a `DataRegistroCOI`, e é contado
**uma vez**, no instante dessa primeira entrada.

- Tipos: **Incidente** (`I`) e **Solicitação** (`R`).
- Não há filtro de analista, categoria, status, prioridade ou motivo.
- O período filtra a `DataRegistroCOI`, **não** a data de abertura. Um chamado
  aberto em outra fila em janeiro e transferido ao COI em março é registrado em
  **março**.

### Como a entrada é identificada

A evidência principal é a **cadeia real de transferências de grupo** do chamado,
lida no histórico de eventos:

- **Abertura direta.** Se a primeira transferência de grupo do chamado **sai**
  do COI, ele já estava no COI antes dela: nasceu no COI. A entrada é a abertura.
- **Transferência.** Se o chamado nasceu em outra fila, a entrada é a
  **primeira** transferência cujo destino é o COI.
- **Sem transferência nenhuma.** Se o chamado nunca mudou de grupo, vale a fila
  em que ele permaneceu: se o grupo atual é o COI, ele nasceu e ficou no COI, e a
  entrada é a abertura.

Além disso, a automação oficial **Task Scheduler / SESUC** registra chamados em
nome do COI direto na fila do NSTI ou do fornecedor. Esses chamados também
contam, pela regra da seção [5](#5-automações).

### Quem é candidato

Só dois caminhos levam uma `DataRegistroCOI` para dentro do período:

- o chamado **abriu** dentro do período; ou
- houve **transferência para o COI** dentro do período, qualquer que seja a data
  de abertura do chamado.

Os candidatos são a união dos dois. Um chamado aberto há anos em outro núcleo e
transferido ao COI dentro do período entra, sem limite de idade.

### Reentradas contam uma vez

A primeira entrada é procurada em **toda a vida** do chamado, e só depois o
período é aplicado. Um chamado que entrou no COI em janeiro, saiu e voltou em
fevereiro é de **janeiro** e não é registrado de novo em fevereiro.

### Um chamado, uma linha

A regra produz exatamente uma linha por SDM. Isso é garantido pela forma da
regra — cada etapa escolhe um único evento ou calcula um único valor por
chamado —, e não por remoção de duplicatas no final. A consulta de validação
confere isso a cada execução.

### Leitura do histórico

Transferência de grupo e transferência de responsável gravam o mesmo tipo de
evento (`TR`). A regra só considera transferência de **grupo** o evento que traz
uma destas expressões: `Grupo de`, `Grupo alterado de`, `Grupo transferido de`,
`Group from` ou `Group changed from`. Origem e destino são os nomes entre aspas
simples que vêm depois dela.

Um evento cuja origem está em branco — `Grupo de '' para 'COI'` — é mantido:
ele prova a entrada pelo destino, mesmo sem dizer de onde o chamado veio.

### Quem conta como COI no histórico

O histórico grava o **nome** do grupo como ele era no instante do evento. Por
isso a regra reconhece a fila do COI por uma lista explícita de nomes, e não pelo
cadastro atual de grupos:

| Nome no evento | Tratamento |
|---|---|
| `COI` | É o COI |
| `10-COI` | É o COI — foi o nome da fila durante a transição de contrato |
| `Contrato 7/2023 - COI` | **Depende da posição** — ver abaixo |

`Contrato 7/2023 - COI` é o nome que a fila **antiga** do COI recebeu quando o
contrato mudou, em 18/03/2026:

- **como destino**, não conta como entrada no COI: transferir um chamado para
  essa fila é mandá-lo para o contrato encerrado;
- **como origem**, num chamado aberto **antes** da mudança de contrato, prova que
  o chamado já estava no COI desde a abertura — o evento grava o nome novo só
  porque aconteceu depois da renomeação.

Transferências entre `COI` e `10-COI` são movimentação interna do COI e não
geram entrada nova.

### Janela de transição

A renomeação das filas ocorreu entre **18/03/2026 20:35:51** e **18/03/2026
21:48:58**. Para chamados abertos **dentro** desse intervalo não se sabe com que
nome a fila antiga operava, então a regra não deduz a entrada a partir da origem
nem do grupo atual. Havendo transferência com destino COI, ela prova a entrada e
dá a data. Não havendo, o chamado fica fora do indicador, como ressalva.

### Casos que ficam fora, com ressalva

Chamados que não podem ser datados com segurança **não entram** no indicador,
mas também não somem: a consulta de validação e a consulta por evidência os
listam pelo número.

| Ressalva | Situação |
|---|---|
| `SEM_RECONSTRUCAO_EVENTO_ILEGIVEL` | Houve mudança de grupo, mas nenhum evento permite ler origem e destino. Também se aplica ao chamado aberto antes da mudança de contrato cuja primeira transferência legível sai de `Contrato 7/2023 - COI`, quando há evento ilegível antes dela |
| `CONTRADICAO_INIT_x_CADEIA` | O histórico sugere que o chamado já era do COI, mas o registro de criação nomeia outra fila |
| `INIT_CONTRATO_INCOMPATIVEL_COM_DATA_ABERTURA` | O registro de criação traz `Contrato 7/2023 - COI` num chamado aberto antes de a fila ter esse nome |
| `AMBIGUO_JANELA_TRANSICAO` | Chamado aberto na janela de transição sem nenhuma entrada demonstrável no COI |

Chamados cuja cadeia nunca toca o COI e que não têm outra evidência ficam
simplesmente fora, sem ressalva.

---

## 4. `DataRegistroCOI`

É a data e hora da **primeira entrada** do chamado no COI. Cada chamado recebe
uma **evidência** — o motivo pelo qual entrou —, e a evidência determina de onde
vem a data.

| Evidência | Quando se aplica | `DataRegistroCOI` |
|---|---|---|
| `ABERTO_NO_COI_CADEIA` | A primeira transferência de grupo sai do COI: o chamado nasceu no COI | Abertura |
| `JA_ESTAVA_NO_COI_HISTORICO` | A primeira transferência sai de `Contrato 7/2023 - COI`, o chamado abriu antes da mudança de contrato e nada contradiz isso | Abertura |
| `TRANSFERIDO_PARA_COI` | O chamado nasceu em outra fila, identificada no histórico | Primeira transferência com destino COI |
| `ENTRADA_DEMONSTRAVEL_DESTINO` | A origem da primeira transferência não prova onde o chamado nasceu — está em branco, ou é `Contrato 7/2023 - COI` num chamado aberto na janela de transição —, mas há transferência com destino COI | Primeira transferência com destino COI |
| `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL` | Nenhuma transferência de grupo em toda a vida, e o grupo atual é o COI | Abertura |
| `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO` | Nenhuma transferência de grupo, o grupo atual é a fila antiga do COI e o chamado abriu antes da mudança de contrato | Abertura |
| `AUTOMACAO_TASK_SCHEDULER` | Registrado pela automação oficial do COI em fila de destino (seção [5](#5-automações)) | Abertura |

### Ordem de decisão

1. **Cadeia real de transferências** — consultada primeiro, e vence sempre.
2. **Travas e ressalvas** do histórico e da janela de transição.
3. **Grupo atual**, somente quando o chamado **nunca** mudou de grupo.
4. **Automação Task Scheduler**, como último recurso.

A automação vem por último de propósito: nenhum chamado que já entra pela cadeia,
pelo histórico ou pelo grupo atual muda de evidência ou de data por causa dela.
Ela só alcança chamados que, sem ela, ficariam de fora.

Consequência dessa ordem: um chamado elegível pela automação que tenha evento de
grupo ilegível continua na ressalva `SEM_RECONSTRUCAO_EVENTO_ILEGIVEL`. A
consulta de validação conta esses casos.

### O registro de criação é auxiliar

O evento de criação (`INIT`) traz a marca `%GROUP=`, com o valor que o programa
de criação informou. Ela **não decide** a data: o valor informado nem sempre é o
grupo em que o chamado efetivamente nasceu, e a cadeia real prevalece. A marca
serve para:

- auditoria — as colunas `GrupoInit` e `InitConsistenteComReconstrucao` (ver
  [seção 10](#grupoinit-primeiraorigemgrupo-e-primeirodestinogrupo));
- trava — impede a leitura histórica quando contradiz a origem (as duas
  ressalvas de `INIT` da seção anterior);
- um dos três termos da automação Task Scheduler.

O valor de `%GROUP=` vai até o próximo `%`. O de `%FROM_USERID=`, que costuma ser
a última marca do texto, vai até o primeiro `%` ou fim de linha. Quebras de linha
e tabulações viram espaço antes de qualquer comparação.

---

## 5. Automações

A gestão do COI informou três modalidades oficiais de automação. Só uma delas
decide se o chamado entra no indicador.

### Task Scheduler / SESUC — decide pertencimento

Os três termos precisam valer **ao mesmo tempo**, no primeiro registro de criação
do chamado:

1. o texto contém `Criado via interface CMD`;
2. `%FROM_USERID=` é `servicedesk`;
3. `%GROUP=` é uma das filas da lista oficial.

A lista oficial é fechada:

| Filas |
|---|
| `Fornecedores - A2B`, `Fornecedores - AMM`, `Fornecedores - Bull` |
| `Fornecedores Bull - 41/2022 - G1 - FA1/FA2`, `Fornecedores Bull - 41/2022 - G2 - FB1` |
| `Fornecedores Bull - 45/2020 - G1 - FA3/FA4/FA5`, `Fornecedores Bull - 45/2020 - G2 - FB2`, `Fornecedores Bull - 45/2020 - G3 - FA-NAS-1 / FB3` |
| `Fornecedores - Decision` |
| `NSTI Rede`, `NSTI Segurança`, `NSTI Aplicação`, `NSTI AD-Workplace`, `NSTI BD`, `NSTI BI-Analytics`, `NSTI SO`, `NSTI GCM`, `NSTI Plan-Doc` |
| `COI` |

**O Task Scheduler registra direto na fila do NSTI ou do fornecedor.** Esses
chamados nunca passam pela fila do COI e não têm transferência de grupo com
origem ou destino no COI. Por isso a automação tem evidência própria,
`AUTOMACAO_TASK_SCHEDULER`, datada na **abertura** — o único instante
demonstrável do registro. Essa evidência não afirma que o chamado passou pelo
COI; afirma que o COI o registrou por automação oficial.

Fora da lista, não entra pela automação. Um chamado criado via CMD por
`servicedesk` com `%GROUP=` de outra fila não é classificado como Task Scheduler,
e a consulta de validação conta esses casos. `10-COI` também não está na lista:
chamados com esse grupo entram, quando entram, pela cadeia real.

### Zabbix Monitor — só classifica

Chamado do tipo **Incidente** aberto pela conta técnica `usr_automacoes` — o
campo *Relatado por* da tela. Os chamados do Zabbix nascem no COI e já entram
pela cadeia real. A classificação não cria linha nem muda data. Se a conta não
existir no cadastro, nenhum chamado é marcado como Zabbix, e nenhum entra ou sai
por isso.

### Robô COI / Copilot Studio — só classifica

Reconhecido por uma assinatura técnica observada no registro de criação: criado
via CMD, com **duas** ocorrências de `%FROM_USERID=` e ao menos uma de `%TYPE=`.
Como é uma correlação observada, e não um critério declarado pela gestão, também
**só classifica**. Os chamados do robô já entram pela cadeia ou pelo grupo atual.

### `TipoAutomacaoCOI` e `EvidenciaRegistroCOI`

São duas informações independentes:

| Coluna | Responde | Valores |
|---|---|---|
| `EvidenciaRegistroCOI` | **Por que e quando** o chamado entrou no indicador | As evidências da seção [4](#4-dataregistrocoi) |
| `TipoAutomacaoCOI` | **De onde veio** o registro | `Task Scheduler / SESUC`, `Zabbix Monitor`, `Robo COI` ou `Não automatizado` |

Um chamado do Zabbix e um do Robô COI costumam ter a mesma evidência,
`ABERTO_NO_COI_CADEIA`: a evidência não os distingue, a modalidade sim. Quando
mais de uma assinatura se aplica, vale a primeira nesta ordem: Task Scheduler,
Zabbix, Robô COI. A consulta de validação mede a sobreposição entre Robô COI e
Task Scheduler.

---

## 6. Chamados Encerrados

`queries/consulta_coi_encerrados.sql` lista, um a um, os chamados encerrados pelo
COI. **Encerrado pelo COI** é o chamado que cumpre tudo abaixo:

| Critério | Regra |
|---|---|
| Data | A **data de fechamento** cai no período — início incluído, fim excluído |
| Tipo | Incidente (`I`) ou Solicitação (`R`) |
| Status | `CL` ou `CLUNRSLV` |
| Grupo | O **grupo atual** do chamado é o **grupo alvo** da apuração |

### Grupo alvo

O COI tem dois grupos: a fila `COI` (`@COI_Novo`) e a fila antiga, hoje chamada
`Contrato 7/2023 - COI` (`@COI_Antigo`). Os dois coexistiram durante a mudança de
contrato, com membros ativos.

- Cada apuração usa **um** grupo, escolhido por quem apura conforme o contrato
  conferido. Para produção e contrato vigente, `@COI_Novo`.
- **Não** se somam os dois grupos: a soma junta dois contratos na mesma
  apuração.
- **Não** se escolhe o grupo pela data: como os dois coexistiram, qualquer corte
  por data erra nos dois sentidos.

O grupo é identificado pelo **UUID**, não pelo nome. Antes da contagem, a
consulta confere se o grupo alvo existe, está ativo e tem ao menos um membro. Se
não passar, o resultado sai **vazio** e uma mensagem explica o motivo — para que
um grupo inválido não se confunda com um período sem encerramentos.

### Saída

Uma linha por SDM, ordenada por data de encerramento:

`SDM`, `Tipo Chamado`, `Símbolo` (categoria), `Resumo`, `Item de Configuração`,
`Prioridade`, `Status`, `Código Status`, `Data de Abertura`, `Data de
Encerramento`, `Data de Resolução`, `Responsável`, `Grupo Atual`, `UUID Grupo
Atual`.

Com `@MostrarDiagnostico = 1`, um segundo resultado mostra o grupo alvo, o total
de linhas e de SDMs distintos, e a quebra por tipo e por status.

### Registrados e Encerrados não são o mesmo universo

- Registrado usa a **primeira entrada** no COI; Encerrado usa o **fechamento**.
- Registrado reconhece a fila pelo **nome gravado em cada evento**, porque
  precisa saber onde o chamado estava no passado. Encerrado usa o **grupo atual**
  pelo UUID, porque pergunta a que contrato o chamado pertence hoje. A diferença
  é proposital.
- Um chamado registrado pelo COI pode ser transferido e fechado por outra fila:
  entra em Registrados e não em Encerrados.
- Um chamado encerrado no período pode ter entrado no COI antes dele: entra em
  Encerrados e não em Registrados.

Por isso **Registrados − Encerrados não é o estoque em aberto do COI**, e a
diferença entre os dois números não deve ser lida como backlog.

---

## 7. Registrados × Encerrados por dia

`queries/consulta_coi_registrados_encerrados_diario.sql`. Uma linha por dia do
período, inclusive os dias sem movimento.

| Coluna | Significado | Data que alimenta |
|---|---|---|
| `Dia` | O dia do calendário | — |
| `Registrados` | Chamados cuja **primeira entrada no COI** caiu nesse dia | `DataRegistroCOI` |
| `Encerrados` | Chamados que o COI **fechou** nesse dia | Data de fechamento |

As duas séries são calculadas **separadamente**, cada uma com a sua regra, e só
se encontram no dia:

- `Registrados` usa a regra de Registrados (seções [3](#3-chamados-registrados)
  a [5](#5-automações));
- `Encerrados` usa a regra de Encerrados (seção
  [6](#6-chamados-encerrados)), com o grupo alvo declarado no próprio arquivo.

Um mesmo chamado pode aparecer em Registrados num dia e em Encerrados em outro,
só numa das séries, ou em nenhuma. Incidentes e Solicitações vêm juntos.

---

## 8. Registrados por mês

`queries/consulta_coi_registrados_mensal.sql`. Uma linha por mês do período,
inclusive meses sem registro.

| Coluna | Significado |
|---|---|
| `Ano`, `Mes` | O mês da `DataRegistroCOI` |
| `MesAno` | O mesmo mês em texto `AAAA-MM`, que ordena corretamente e não depende do idioma do servidor |
| `Incidentes` | Registrados do tipo Incidente no mês |
| `Solicitacoes` | Registrados do tipo Solicitação no mês |
| `Total` | `Incidentes` + `Solicitacoes` |

---

## 9. Por hora

### Registrados por hora

`queries/consulta_coi_registrados_por_hora.sql`. Mostra **em que hora do dia**
os chamados entram no COI: é a distribuição pela **hora da `DataRegistroCOI`**,
em horário de Brasília.

- Há uma linha para **cada combinação de mês e hora**: 24 linhas por mês, de
  `00h` a `23h`, inclusive as horas sem registro.
- Dentro de um mês, **todos os dias são somados** na mesma hora.
- Colunas: `Ano`, `Mes`, `MesAno`, `Hora` (0 a 23), `HoraLabel` (`00h` … `23h`)
  e `QtdRegistrados`.

```text
00h → registros cuja primeira entrada no COI ocorreu entre 00:00:00 e 00:59:59
01h → entre 01:00:00 e 01:59:59
...
23h → entre 23:00:00 e 23:59:59
```

As 24 horas de um mês somam o `Total` daquele mês na consulta mensal.

### Encerrados por hora

`queries/consulta_coi_encerrados_por_hora.sql`. A mesma forma, para
Encerrados: a população é a da seção [6](#6-chamados-encerrados), com a regra e
a conferência do grupo alvo copiadas literalmente, e a hora é a da **data de
fechamento**, em horário de Brasília — nunca a hora de registro.

- 24 linhas por mês, inclusive as horas sem encerramento.
- Colunas: `Ano`, `Mes`, `MesAno`, `Hora`, `HoraLabel` e `QtdEncerrados`.
- As 24 horas do período somam as linhas de `consulta_coi_encerrados.sql`.
- Parâmetros: `@DataInicio`, `@DataFim`, `@COI_GrupoAlvo`. Com grupo alvo
  inválido, o resultado sai vazio, como em Encerrados.

### Registrados × Encerrados por hora

`queries/consulta_coi_registrados_encerrados_por_hora.sql`. As duas
distribuições acima na mesma linha: uma linha por **mês e hora**, 24 por mês,
inclusive as horas sem movimento.

| Coluna | Significado | Hora usada |
|---|---|---|
| `Ano`, `Mes`, `MesAno`, `Hora`, `HoraLabel` | A célula do calendário | — |
| `Registrados` | Chamados cuja **primeira entrada no COI** caiu naquela hora do mês | Da `DataRegistroCOI` |
| `Encerrados` | Chamados que o COI **fechou** naquela hora do mês | Do `close_date` |

As duas séries são calculadas **separadamente**, cada uma com a sua regra —
`Registrados` pelo bloco canônico, `Encerrados` pela regra da seção
[6](#6-chamados-encerrados), com a conferência do grupo alvo —, e cada uma é
agregada sozinha por mês e hora antes de se juntar ao calendário. Não há junção
entre chamados das duas populações, e por isso nenhuma linha se multiplica. Um
mesmo chamado pode contar em `Registrados` numa hora e em `Encerrados` em outra.

Para o mesmo período, `Registrados` é igual a `QtdRegistrados` de
`consulta_coi_registrados_por_hora.sql` e `Encerrados` é igual a `QtdEncerrados`
de `consulta_coi_encerrados_por_hora.sql`, em cada mês e hora. Parâmetros:
`@InicioBR`, `@FimBR` e `@COI_GrupoAlvo`; com grupo alvo inválido, a série
`Encerrados` sai zerada, como no diário.

---

## 10. Registrados por evidência e detalhe

### Por evidência

`queries/consulta_coi_registrados_por_evidencia.sql` mostra a composição dos
Registrados em duas seções.

**`1-NO INDICADOR`** — o que entra no indicador:

| `EvidenciaRegistroCOI` | `ForcaDaEvidencia` |
|---|---|
| `ABERTO_NO_COI_CADEIA` | CADEIA: origem do 1º evento de grupo já é COI |
| `JA_ESTAVA_NO_COI_HISTORICO` | CADEIA: origem é o nome posterior da fila COI antiga |
| `TRANSFERIDO_PARA_COI` | CADEIA: nasceu fora, 1ª transferência da vida com destino COI |
| `ENTRADA_DEMONSTRAVEL_DESTINO` | CADEIA: origem não prova a 1ª entrada, destino prova |
| `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL` | FALLBACK: sem evento de grupo, permaneceu no COI |
| `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO` | FALLBACK: sem evento, UUID antigo, aberto antes da transição |
| `AUTOMACAO_TASK_SCHEDULER` | AUTOMAÇÃO: registro oficial do COI direto na fila destino |

**`2-RESSALVA`** — o que ficou de fora, com o motivo: as quatro ressalvas da
seção [3](#casos-que-ficam-fora-com-ressalva).

Colunas: `Secao`, `EvidenciaRegistroCOI`, `AliasEvidencia` (o nome de grupo que
sustentou a evidência), `ForcaDaEvidencia`, `Incidentes`, `Solicitacoes`,
`Total`.

### Detalhe

`queries/consulta_coi_registrados_detalhe.sql` devolve **uma linha por SDM** da
população de Registrados. É a prova nominal do total.

| Grupo de colunas | Colunas |
|---|---|
| Identificação e data | `SDM`, `DataAbertura`, `DataRegistroCOI`, `DataRegistro`, `HoraRegistro` |
| Descrição | `Categoria` (`prob_ctg.sym`, `N/A` sem categoria) e `Resumo` (`call_req.summary`), logo depois de `SDM` |
| Como entrou | `FormaRegistroCOI`, `EvidenciaRegistroCOI`, `TipoAutomacaoCOI`, `AliasEvidencia` |
| Tipo | `TipoCodigo`, `Tipo` |
| Quem abriu | `RegistradorUUID`, `RegistradorUserID`, `RegistradorNome` |
| Cadeia de transferências | `PrimeiraOrigemGrupo`, `PrimeiroDestinoGrupo`, `DataPrimeiroEventoGrupo`, `QtdEventosGrupo`, `QtdAncorasGrupo`, `QtdAncorasAntesDo1oLegivel`, `DataPrimeiraEntradaNoCOI` |
| Registro de criação | `GrupoInit`, `InitConsistenteComReconstrucao` |
| Estado atual | `UUIDGrupoAtual`, `GrupoAtual` |
| Conferência | `AbertoAntesDoPeriodo`, `Anomalia` |

`FormaRegistroCOI` traduz a evidência técnica para leitura:

| `FormaRegistroCOI` | `EvidenciaRegistroCOI` |
|---|---|
| Aberto no COI | `ABERTO_NO_COI_CADEIA` |
| Já estava no COI histórico | `JA_ESTAVA_NO_COI_HISTORICO` |
| Transferido para o COI | `TRANSFERIDO_PARA_COI` |
| Entrada identificada pelo destino | `ENTRADA_DEMONSTRAVEL_DESTINO` |
| Aberto no COI - inferido | `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL` e `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO` |
| Registrado por automação do COI | `AUTOMACAO_TASK_SCHEDULER` |

As duas evidências de grupo atual compartilham o mesmo texto; quem precisa
separá-las usa `EvidenciaRegistroCOI`. Uma evidência sem tradução aparece como
`Outro - <evidência>`, nunca vazia.

As colunas de quem abriu, do grupo atual e da cadeia são **informativas**:
nenhuma delas altera a população, a data ou a evidência. Um chamado cujo
registrador não existe no cadastro continua na lista, com o UUID preenchido e o
nome marcado como não resolvido.

### `GrupoInit`, `PrimeiraOrigemGrupo` e `PrimeiroDestinoGrupo`

As três colunas têm finalidades diferentes e **não precisam coincidir**:

| Coluna | O que representa | De onde vem | Sem valor |
|---|---|---|---|
| `GrupoInit` | O valor informado em `%GROUP=` no evento de criação do chamado. É informação auxiliar e pode não coincidir com o grupo em que o chamado nasceu | Evento `INIT`; havendo mais de um, o mais antigo | `(sem %GROUP= no INIT)` |
| `PrimeiraOrigemGrupo` | O grupo de origem da primeira transferência de grupo legível do histórico. Quando há transferência, é a principal evidência de onde o chamado estava antes do primeiro movimento | Primeiro evento `TR` de grupo legível | `(origem não legível)` |
| `PrimeiroDestinoGrupo` | O grupo de destino dessa mesma primeira transferência: a fila seguinte ao primeiro movimento, que não precisa ser o COI | O mesmo evento | `(sem evento de grupo)` |

As três saem normalizadas: em maiúsculas, com espaços repetidos reduzidos a um.
Em `GrupoInit`, quebras de linha e tabulações também viram espaço. Os acentos são
mantidos.

Quando o chamado **não tem nenhuma transferência de grupo** (`QtdEventosGrupo` = 0),
`PrimeiraOrigemGrupo` mostra `(origem não legível)` e `PrimeiroDestinoGrupo` mostra
`(sem evento de grupo)`. Nesse caso, a regra usa o grupo atual (seção
[4](#4-dataregistrocoi)).

**`GrupoInit` diferente de `PrimeiraOrigemGrupo` não é erro.** Significa que o
programa de criação informou um valor e o chamado nasceu em outro grupo. A coluna
`InitConsistenteComReconstrucao` mostra se o registro de criação e a evidência
usada concordam sobre o chamado ter nascido ou não no COI: `sim` quando
concordam, `NAO - cadeia contradiz o INIT` quando não.

Nenhuma das três decide, sozinha, a entrada no indicador. A classificação usa a
cadeia real de transferências e as demais regras das seções [3](#3-chamados-registrados)
a [5](#5-automações). O `%GROUP=` só participa da decisão no critério da automação
Task Scheduler.

**Exemplo — SDM 1658863.**

| Momento | Evento |
|---|---|
| 20/11/2025 09:00:01 | Criação via CMD por `servicedesk`, com `%GROUP=Virtual TI.Elaborar/Manter Documentação` |
| 20/11/2025 09:11:09 | `Transferir Grupo de 'COI' para 'Fornecedores - Virtual'` |

| Coluna | Valor |
|---|---|
| `GrupoInit` | `VIRTUAL TI.ELABORAR/MANTER DOCUMENTAÇÃO` |
| `PrimeiraOrigemGrupo` | `COI` |
| `PrimeiroDestinoGrupo` | `FORNECEDORES - VIRTUAL` |
| `InitConsistenteComReconstrucao` | `NAO - cadeia contradiz o INIT` |
| `EvidenciaRegistroCOI` | `ABERTO_NO_COI_CADEIA` |
| `DataRegistroCOI` | 20/11/2025 09:00:01 (a abertura) |

O valor de `%GROUP=` desse chamado é o nome de uma categoria, não de uma fila. A
primeira transferência mostra que ele nasceu no COI, e é essa cadeia que o
registra no indicador: evidência `ABERTO_NO_COI_CADEIA`, datado na abertura.

---

## 11. Por registrador e por membro

### Registrados por registrador

`queries/consulta_coi_registrados_por_registrador.sql` agrupa a população de
Registrados por **quem abriu** o chamado (`log_agent`).

- O agrupamento é pelo identificador do contato, não pelo nome: dois contatos
  com o mesmo nome não se fundem.
- Contas técnicas (`usr_automacoes`, `Sesuc Automacao` e semelhantes) aparecem
  normalmente; escondê-las mudaria o total.
- Quem abriu **não** é, necessariamente, quem trouxe o chamado para o COI. Num
  chamado transferido, é quem o abriu na fila de origem. As colunas por evidência
  deixam isso visível.

| Coluna | Significado |
|---|---|
| `RegistradorUUID`, `RegistradorUserID`, `Nome` | Quem abriu |
| `Solicitacoes`, `Incidentes`, `Total` | Registrados daquele registrador |
| `Cadeia_AbertoNoCOI`, `Cadeia_JaEraCOIHistorico`, `Cadeia_Transferido`, `Cadeia_EntradaPorDestino`, `Fallback_GrupoAtual`, `Fallback_Historico`, `Automacao_TaskScheduler` | Quebra do `Total` por evidência; as sete somam o `Total` |
| `InitContraditoPelaCadeia` | Quantos tiveram o `%GROUP=` do registro de criação contradito pela cadeia |

### Registrados × Encerrados por membro

`queries/consulta_coi_registrados_encerrados_por_membro.sql`. Uma linha por
**mês e conta**, com quantos chamados a conta registrou e quantos encerrou no
mês. As duas populações são as oficiais — Registrados pelo bloco canônico,
Encerrados pela regra da seção [6](#6-chamados-encerrados) — e só a
**atribuição** é nova:

| Série | A quem se atribui | Mês |
|---|---|---|
| `Registrados` | Quem **abriu** o chamado (`log_agent`), como no por registrador | Da `DataRegistroCOI` |
| `EncerradosComoResponsavel` | O **responsável** do chamado (`assignee`) — **critério do fornecedor, usado no painel** | Da data de fechamento |
| `Encerrados` | Quem **executou o encerramento**: o autor do último evento `CL`, `ST`, `CLREQ`, `RE`, `RO` ou `SOLN` do histórico com instante até o fechamento; empate no mesmo segundo desfeito pelo maior `id`. Só auditoria | Da data de fechamento |

**O indicador Por Membro segue o critério do fornecedor.** A tabela por analista
do relatório do fornecedor atribui cada encerramento ao **responsável** do
chamado, e é isso que `EncerradosComoResponsavel` faz. Conferido nos relatórios
de março (09/03 a 31/03) e de junho de 2026: o responsável da consulta é o do
relatório em todos os chamados comuns (471 de 471 e 612 de 612), e a contagem
por analista reproduz a tabela do relatório, nome a nome. As únicas diferenças
são de grafia do nome no relatório e os 5 chamados de março que a consulta conta
e o relatório não (seção [6](#6-chamados-encerrados)).

**Quem executou o encerramento não é, necessariamente, o responsável.** No SDM,
o fechamento grava um evento `CL` no mesmo segundo do `close_date`, ou vem logo
depois de uma solução (`SOLN`); o autor desse evento é quem executou o
encerramento — muitas vezes a automação `Sesuc Automação`. De abril a setembro
de 2026, o autor e o responsável diferem em 755 de 3.558 encerramentos (21%).
Por isso `Encerrados` fica na consulta só para auditoria e comparação. As colunas
`Encerrados` e `EncerradosComoResponsavel` são duas atribuições dos mesmos
chamados: cada uma soma o total de Encerrados, e não se somam entre si.

O histórico é usado **só para atribuir** um encerramento já contado. A
população continua sendo a do grupo atual; não se volta à regra de Encerrados
por grupo no momento do fechamento, abandonada no histórico do projeto. Nenhum
texto de evento é interpretado.

`TipoConta` classifica cada conta:

| `TipoConta` | Critério |
|---|---|
| `Conta técnica / automação` | `usr_automacoes`, `sesuc_auto` ou userid/nome com `SERVICEDESK` / `SERVICE DESK` |
| `Membro do grupo COI` | Consta hoje em `grpmem` de `@COI_Novo` ou de `@COI_Antigo` |
| `Fora do grupo COI` | Pessoa que não é membro de nenhum dos dois grupos |
| `Não identificado` | Encerramento sem responsável (`EncerradosComoResponsavel`) ou sem evento de fechamento ou de solução no histórico (`Encerrados`) |

`TipoConta` é informativa e **não filtra** o indicador. `grpmem` guarda a
composição **atual** dos dois grupos: quem saiu da equipe aparece como `Fora do
grupo COI` também nos meses em que era membro, e analistas que o relatório do
fornecedor lista no COI mas que não constam hoje de `grpmem` também aparecem
como `Fora do grupo COI`. Pelo critério do responsável, nenhum encerramento cai
em conta técnica.

Colunas: `Ano`, `Mes`, `MesAno`, `MembroUUID`, `MembroUserID`, `Membro`,
`TipoConta`, `Registrados`, `Encerrados`, `EncerradosComoResponsavel`. Uma conta
aparece no mês se tiver ao menos um valor diferente de zero. Parâmetros:
`@InicioBR`, `@FimBR`, `@COI_GrupoAlvo` e `@MostrarDiagnostico` — este, ligado,
acrescenta um segundo resultado com cada encerramento, quem encerrou, o evento
usado, os segundos até o fechamento e o responsável atual.

---

## 12. Membros, contas técnicas e universo bruto

Estas três consultas servem à **conciliação com os relatórios do fornecedor** e
usam **outro modelo de apuração**:

- contam pela **data de abertura** do chamado, e não pela `DataRegistroCOI`;
- identificam o COI por **quem abriu** o chamado, e não pela passagem pela fila;
- trabalham com **períodos de conferência fixos**, declarados no início de cada
  arquivo, porque dependem de uma lista de analistas por período.

Seus números **não são comparáveis** com os das consultas de Registrados.

### Membros

`queries/consulta_coi_registrados_membros.sql`. Chamados Incidente ou
Solicitação **abertos no período** por um analista que consta da lista de
analistas do COI **daquele período**. Sem filtro de grupo, de histórico, de
status ou de categoria.

A lista de analistas é transcrita, para cada período, da tabela por analista do
relatório do fornecedor. Não se usa a composição atual do grupo, porque a equipe
muda entre períodos. Cada nome da lista é ligado a um contato do cadastro por
comparação de nomes normalizados; um contato corresponde a um único nome por
período, o que impede duplicar chamado.

| Resultado | Conteúdo |
|---|---|
| 1 — resumo por período | Incidentes, Solicitações, total, analistas com chamado, linhas × SDMs distintos, duplicados, e os totais do relatório como referência |
| 2 — por analista | Cada analista da lista, com zero quando não abriu chamado, e aviso quando o nome não foi encontrado no cadastro |
| 3 — detalhe | Uma linha por SDM |

Os totais do relatório do fornecedor (`S_RSP_referencia`, `I_RSP_referencia`)
aparecem só para conferência; nenhum critério os usa.

### Contas técnicas

`queries/consulta_coi_registrados_total_com_tecnicos.sql`. Soma aos membros os
chamados abertos pelas contas técnicas compartilhadas — `ServiceDesk`,
`usr_automacoes` e `sesuc_auto` — **somente quando a origem no COI é
comprovada**:

1. o `%GROUP=` do registro de criação é do COI; ou
2. a origem da primeira transferência de grupo é do COI.

Sem uma das duas, o chamado fica fora. O grupo atual não é usado. As três origens
— membro, técnico por registro de criação, técnico por histórico — não se
sobrepõem.

| Resultado | Conteúdo |
|---|---|
| 1 — resumo por período | Incidentes, Solicitações, total, SDMs distintos, duplicados e técnicos sem origem comprovada, que ficaram fora |
| 2 — origem do total | O total separado nas três origens |
| 3 — detalhe | Uma linha por SDM do total, com a origem e a evidência |

### Universo bruto

`queries/consulta_coi_registrados_universo_bruto.sql`. Auditoria da anterior:
**todos** os chamados das contas técnicas, sem filtrar origem, cada um
classificado:

| Classificação | Significado |
|---|---|
| `TECNICO_COI_ORIGEM_CONFIRMADA_INIT` | Registro de criação aponta o COI |
| `TECNICO_COI_ORIGEM_CONFIRMADA_HISTORICO` | Primeiro grupo do histórico é o COI |
| `TECNICO_ORIGEM_OUTRO_NUCLEO_INIT` | Registro de criação aponta outro núcleo |
| `TECNICO_ORIGEM_OUTRO_NUCLEO_HISTORICO` | Primeiro grupo do histórico é outro núcleo |
| `TECNICO_ORIGEM_NAO_COMPROVADA` | Nenhuma evidência |

O **universo bruto não é o total do COI**: parte dele é trabalho de outros
núcleos. A coluna `EntraNoTotalCOI` diz, em cada linha, se ela entra no total
demonstrável. As duas consultas de contas técnicas compartilham o mesmo texto de
regra, para que o universo bruto seja de fato a auditoria do total.

| Resultado | Conteúdo |
|---|---|
| 1 — resumo | Cada parcela, o universo bruto e o total demonstrável, com a ressalva em cada linha |
| 2 — por conta técnica | Por conta, classificação e grupo de origem: de quais núcleos vem o volume |
| 3 — detalhe | Uma linha por SDM do universo bruto |

---

## 13. Validação

`queries/consulta_coi_registrados_validacao.sql` confere a regra de Registrados
num período. Devolve quatro resultados.

### 1 — Sanidade

Uma linha com o período, a janela de transição, os totais, a quebra por
evidência, as ressalvas e **16 asserções**, cada uma com `SIM` ou `NAO`:

| # | Asserção | O que garante |
|---|---|---|
| 1 | `SemDuplicidade` | Linhas = SDMs distintos |
| 2 | `SomenteIR` | Só Incidentes e Solicitações |
| 3 | `EvidenciaCompleta` | Toda linha tem exatamente uma evidência |
| 4 | `RegistroNaoAnteriorAAbertura` | Nenhuma `DataRegistroCOI` antes da abertura |
| 5 | `PrimeiraEntradaDaVida` | A data é a primeira entrada, não uma reentrada |
| 6 | `ContratoAntigoNuncaCriaEntradaComoDestino` | Transferir para `Contrato 7/2023 - COI` nunca conta como entrada |
| 7 | `SemPrimeiraEntradaApagada` | Nenhuma primeira entrada demonstrável fica sem contar |
| 8 | `HistoricoNaoContradizInitExplicito` | A leitura histórica respeita o registro de criação |
| 9 | `AmbiguidadeNaoApagaEntradaDemonstravel` | A janela de transição não descarta entrada provada |
| 10 | `AutomacaoNaoDuplicaSDM` | A automação não cria segunda linha |
| 11 | `TaskSchedulerEntraSemPassagemPeloCOI` | Chamados da automação entram mesmo sem passar pela fila |
| 12 | `GrupoForaDaListaNaoEntra` | Fila fora da lista oficial não entra pela automação |
| 13 | `CMDSozinhoNaoViraTaskScheduler` | Criado via CMD, sozinho, não basta |
| 14 | `ZabbixPermaneceTipoI` | Zabbix só marca Incidentes |
| 15 | `RoboNaoConfundidoComTaskScheduler` | As duas modalidades não se sobrepõem |
| 16 | `AutomacaoUsaDataDeAbertura` | Chamados da automação são datados na abertura |

Se alguma vier `NAO`, a base do período não deve ser usada até a causa ser
entendida. A linha traz também `AvisoPeriodo`, que alerta quando o fim do período
está no futuro — sinal de ano digitado errado.

### 2 — Consistência

O total por mês, por dia e por hora, e o número de SDMs distintos, calculados
sobre a mesma população. Os quatro precisam coincidir.

### 3 — Casos de referência

Chamados que ilustram cada ramo da regra, conferidos um a um: evidência e data
esperadas ao lado das obtidas, com veredito `OK` ou a falha. Um caso fora do
período consultado sai como `FORA DO PERIODO`, o que não é falha.

### 4 — Ressalvas

Os chamados do período que a regra não conta, cada um com o motivo e os dados da
cadeia. Vazio quando nada foi excluído.

---

## 14. Pesquisa de satisfação dos Encerrados

`queries/consulta_coi_pesquisa_satisfacao_encerrados.sql` e, para o painel,
`queries/consulta_coi_pesquisa_satisfacao_encerrados_detalhe.sql` (ver
[Detalhe por chamado](#detalhe-por-chamado)). As duas têm a mesma população e
a mesma classificação.

### População

Os chamados **encerrados pelo COI** no período, pela regra da seção
[6](#6-chamados-encerrados): fechamento no período, Incidente ou Solicitação,
status `CL` ou `CLUNRSLV`, grupo atual igual ao grupo alvo válido. O eixo é a
data de fechamento.

### Como a resposta é localizada

```text
pesquisa do chamado (survey)
  → perguntas da pesquisa (survey_question)
    → opções da pergunta (survey_answer), marcada a que foi escolhida
```

A resposta é a **opção escolhida** pelo usuário. A consulta não lê comentário
livre.

### Qual pergunta é considerada

Cada pesquisa tem cinco perguntas, identificadas pela ordem:

| Ordem | Pergunta | Escala |
|---|---|---|
| 10 | O problema descrito no chamado foi resolvido? | Sim / Não |
| 20 | Qualidade do atendimento telefônico | 5 opções |
| 30 | Qualidade do atendimento do técnico presencial | 5 opções |
| **40** | **Satisfação geral com a execução dos serviços** — padrão | Ótimo / Bom / Regular / Ruim |
| 50 | Satisfação geral com o tempo de atendimento | 4 opções |

A pergunta é escolhida pela **ordem**, não pelo texto do enunciado, em
`@SequenciaPerguntaAvaliada`.

### Várias pesquisas no mesmo chamado

Vale a **mais recente**: a de última modificação mais nova e, em empate, o maior
identificador. Pesquisas excluídas não são consideradas. Respostas de pesquisas
diferentes do mesmo chamado **não se somam**.

### Resultados

| Resultado | Conteúdo |
|---|---|
| Janela 1 — resumo | `Com satisfação` e `Sem satisfação`, com a quantidade de cada |
| Janela 2 — detalhe | Uma linha por SDM com a opção escolhida na pergunta considerada |
| Conferência (`@MostrarConferencia = 1`) | Prova que Com + Sem = total de Encerrados do período e mede a diferença entre as duas janelas |

- **Com satisfação**: a pesquisa do chamado tem ao menos uma pergunta
  respondida, qualquer que seja.
- **Sem satisfação**: não há pesquisa, ou ela não tem nenhuma resposta.

Por isso um chamado pode estar *Com satisfação* na Janela 1 e não aparecer na
Janela 2, se a pergunta considerada ficou em branco. A conferência mede essa
diferença.

### Detalhe por chamado

`queries/consulta_coi_pesquisa_satisfacao_encerrados_detalhe.sql` devolve
**uma linha por chamado encerrado**, com data, para que o filtro de mês do
painel funcione. A classificação é a das duas janelas acima, na mesma linha:

| Coluna | Conteúdo |
|---|---|
| `SDM`, `TipoChamado`, `DataEncerramento`, `Ano`, `Mes`, `MesAno` | O encerramento |
| `StatusSatisfacao` | `Com satisfação` ou `Sem satisfação`, como na Janela 1 |
| `PerguntaAvaliada`, `RespostaSatisfacao` | A pergunta considerada e a opção escolhida, como na Janela 2 |
| `QtdPerguntasRespondidas`, `DataPesquisa` | Perguntas respondidas e última modificação da pesquisa considerada |
| `PesquisaSolicitada`, `QtdSolicitacoesPesquisa`, `DataSolicitacaoPesquisa`, `SolicitacaoPesquisa` | Se o SDM registrou o pedido de pesquisa (evento `SRVY_SENT` do histórico), quantas vezes, e o mais recente |

**Solicitada não é respondida.** O pedido de pesquisa é registrado para a
maioria dos encerramentos (2.550 de 4.036, de março a setembro de 2026), mas só
2 têm resposta. A regra do COI conta as **respondidas** (`StatusSatisfacao`).

### Resultado esperado: quase tudo "Sem satisfação"

O envio de pesquisa **não está habilitado** para as filas do COI; as pesquisas
vão para as filas de atendimento a pessoas. Na maioria dos períodos, *Sem
satisfação* é igual ao total de Encerrados — é o comportamento esperado, não
falha da consulta.

---

## 15. Parâmetros

Todas as datas são em horário de Brasília, com intervalo **semiaberto**: o
início entra, o fim não. Para março inteiro, início `2026-03-01 00:00:00` e fim
`2026-04-01 00:00:00` — nunca `23:59:59`, que deixaria de fora o último segundo
do dia.

| Consultas | Parâmetros |
|---|---|
| Registrados — as sete consultas | `@InicioBR`, `@FimBR` |
| Registrados × Encerrados por dia | `@InicioBR`, `@FimBR`, `@COI_GrupoAlvo` |
| Registrados × Encerrados por membro | `@InicioBR`, `@FimBR`, `@COI_GrupoAlvo`, `@MostrarDiagnostico` |
| Encerrados | `@DataInicio`, `@DataFim`, `@COI_GrupoAlvo`, `@MostrarDiagnostico` |
| Encerrados por hora | `@DataInicio`, `@DataFim`, `@COI_GrupoAlvo` |
| Registrados × Encerrados por hora | `@InicioBR`, `@FimBR`, `@COI_GrupoAlvo` |
| Pesquisa de satisfação | `@DataInicio`, `@DataFim`, `@COI_GrupoAlvo`, `@SequenciaPerguntaAvaliada` (padrão `40`), `@MostrarConferencia` |
| Pesquisa de satisfação, detalhe | `@DataInicio`, `@DataFim`, `@COI_GrupoAlvo`, `@SequenciaPerguntaAvaliada` (padrão `40`) |
| Membros, contas técnicas, universo bruto | Tabela de períodos e lista de analistas no início de cada arquivo |

`@COI_GrupoAlvo` escolhe **um** grupo, `@COI_Novo` ou `@COI_Antigo`, junto com o
período (seção [6](#grupo-alvo)). O valor que vem preenchido não é o mesmo em
todos os arquivos: confira-o antes de comparar resultados entre consultas.

### Valores que não são parâmetros

Dentro da regra de Registrados há valores que **descrevem fatos** e não devem ser
alterados para mudar o período:

| Valor | O que é |
|---|---|
| `@TransIniBR`, `@TransFimBR` | Início e fim da janela de renomeação das filas do COI |
| `@COI_UUID_Antigo`, `@COI_UUID_Novo` | Identificadores das duas filas do COI |
| `#AliasCOI` | Nomes que valem como COI nos eventos: `COI`, `10-COI` |
| `#GrupoTaskSched` | Lista oficial de filas do Task Scheduler |

---

## 16. Limitações

- **Meses fechados podem mudar.** As consultas leem o estado atual da base. Se um
  chamado for corrigido ou incluído depois, com data retroativa, uma execução de
  hoje pode diferir de uma feita meses atrás. A `DataRegistroCOI` de um chamado
  não muda com o tamanho do período consultado, mas a base pode mudar.
- **Relatórios antigos do fornecedor** vieram de outra ferramenta e servem como
  referência de conciliação, não como regra. Nenhum filtro existe para aproximar
  número de relatório antigo.
- **Encerrados usa o grupo de hoje.** Um relatório do fornecedor registra o grupo
  de cada chamado no momento em que foi gerado. Chamado que mudou de grupo depois
  disso aparece de forma diferente na consulta.
- **Ressalvas ficam fora do indicador.** Chamados sem entrada demonstrável no COI
  não são contados; a validação e a consulta por evidência os listam.
- **Conciliação por abertura depende da lista de analistas.** Membros, contas
  técnicas e universo bruto só funcionam para os períodos que têm lista
  transcrita.
- **Satisfação** depende do envio de pesquisa, hoje não habilitado para as filas
  do COI.
- **Membro do COI é a composição atual.** A classificação `TipoConta` do por
  membro usa `grpmem` de hoje, sem histórico de entrada e saída da equipe.
