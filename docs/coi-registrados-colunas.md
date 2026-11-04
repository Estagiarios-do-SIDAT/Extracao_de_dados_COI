# Colunas da tabela de Registrados — guia de leitura

Este guia explica, para quem lê a tabela **Registrados** da página Visão Geral do
painel (ou a planilha da consulta de detalhe), o que cada coluna informa, de onde
ela vem e como interpretá-la. Não é preciso conhecer o SQL.

- **Fonte das colunas:** [`queries/consulta_coi_registrados_detalhe.sql`](../queries/consulta_coi_registrados_detalhe.sql)
  e a sua versão do painel, [`powerbi/consulta_coi_registrados_detalhe_power_bi.sql`](../powerbi/consulta_coi_registrados_detalhe_power_bi.sql).
  As duas devolvem as mesmas colunas, com os mesmos nomes técnicos.
- **Regras de cálculo:** [`docs/coi-calculation.md`](coi-calculation.md) — seções 3
  (quem é Registrado), 4 (`DataRegistroCOI` e evidências), 5 (automações) e 10
  (detalhe). Este guia não repete as regras: explica como ler o resultado delas.
- **Números de exemplo:** os totais e os SDMs citados vêm do painel atualizado em
  04/11/2026, com março a outubro de 2026 carregados (29.545 chamados). Eles
  mudam a cada atualização; servem só para ilustrar.

## Índice

1. [Nomes no painel](#1-nomes-no-painel)
2. [Resumo das colunas explicadas](#2-resumo-das-colunas-explicadas)
3. [As três datas](#3-as-três-datas)
4. [Como o chamado entrou: Forma, Código da Evidência e Tipo de Automação](#4-como-o-chamado-entrou-forma-código-da-evidência-e-tipo-de-automação)
5. [Os quatro grupos](#5-os-quatro-grupos)
6. [Aberto por não é o responsável](#6-aberto-por-não-é-o-responsável)
7. [Por que aparecem filas de fornecedor ou do NSTI](#7-por-que-aparecem-filas-de-fornecedor-ou-do-nsti)
8. [Valores especiais](#8-valores-especiais)
9. [Colunas do modelo que não estão na tabela](#9-colunas-do-modelo-que-não-estão-na-tabela)

---

## 1. Nomes no painel

As tabelas da Visão Geral exibem nomes de leitura. A troca é feita **só no
visual** (renomear para este visual): no SQL, no Power Query e no modelo as
colunas mantêm o nome técnico, e é por ele que se filtra, se exporta e se
consulta.

### Registrados — 16 colunas, nesta ordem

| # | Nome exibido | Coluna técnica | Bloco |
|---|---|---|---|
| 1 | SDM | `SDM` | Identificação |
| 2 | Tipo | `Tipo` | Identificação |
| 3 | Categoria | `Categoria` | Identificação |
| 4 | Resumo | `Resumo` | Identificação |
| 5 | Item de Configuração | `Item de Configuração` | Identificação |
| 6 | Data de Abertura | `DataAbertura` | Datas |
| 7 | Data de Registro no COI | `DataRegistroCOI` | Datas |
| 8 | Data da 1ª Transferência para o COI | `DataPrimeiraEntradaNoCOI` | Datas |
| 9 | Aberto por | `RegistradorNome` | Quem abriu e grupos |
| 10 | Origem da 1ª Transferência | `PrimeiraOrigemGrupo` | Quem abriu e grupos |
| 11 | Destino da 1ª Transferência | `PrimeiroDestinoGrupo` | Quem abriu e grupos |
| 12 | Grupo Atual | `GrupoAtual` | Quem abriu e grupos |
| 13 | Forma de Registro no COI | `FormaRegistroCOI` | Classificação e auditoria |
| 14 | Tipo de Automação | `TipoAutomacaoCOI` | Classificação e auditoria |
| 15 | Código da Evidência | `EvidenciaRegistroCOI` | Classificação e auditoria |
| 16 | Grupo Informado na Criação | `GrupoInit` | Classificação e auditoria |

A tabela abre ordenada pela **Data de Registro no COI**, da mais recente para a
mais antiga.

### Encerrados — 11 colunas, nesta ordem

| # | Nome exibido | Coluna técnica | Origem |
|---|---|---|---|
| 1 | SDM | `SDM` | número do chamado |
| 2 | Tipo | `Tipo Chamado` | Incidente ou Solicitação |
| 3 | Categoria | `Símbolo` | categoria do chamado |
| 4 | Resumo | `Resumo` | resumo do chamado |
| 5 | Item de Configuração | `Item de Configuração` | IC do chamado |
| 6 | Prioridade | `Prioridade` | prioridade, de 1 - Máxima a 5 - Mínima |
| 7 | Status | `Status` | status atual |
| 8 | Data de Abertura | `Data de Abertura` | abertura do chamado |
| 9 | Data de Encerramento | `Data de Encerramento` | fechamento — a data do indicador |
| 10 | Data de Resolução | `Data de Resolução` | resolução registrada no chamado |
| 11 | Responsável | `Responsável` | o responsável atribuído ao chamado (`call_req.assignee`) |

As regras de Encerrados estão na seção 6 de [`coi-calculation.md`](coi-calculation.md).

### Cabeçalhos

Os cabeçalhos das duas tabelas ficam **em uma linha**: a quebra de texto do
cabeçalho está desativada e a largura de cada coluna comporta o título. Quando as
colunas não cabem na área do visual, a tabela rola na horizontal.

---

## 2. Resumo das colunas explicadas

| Nome exibido | Coluna técnica | Responde a |
|---|---|---|
| Data de Registro no COI | `DataRegistroCOI` | **Quando** o chamado entrou no COI pela primeira vez — a data do indicador |
| Forma de Registro no COI | `FormaRegistroCOI` | **Como** ele entrou, em texto de leitura |
| Código da Evidência | `EvidenciaRegistroCOI` | **Como** ele entrou, no código técnico da regra |
| Tipo de Automação | `TipoAutomacaoCOI` | **De onde** veio o registro: qual automação, se alguma |
| Grupo Informado na Criação | `GrupoInit` | Qual fila o programa de criação **declarou** |
| Origem da 1ª Transferência | `PrimeiraOrigemGrupo` | Em que fila o chamado estava **antes do primeiro movimento** |
| Destino da 1ª Transferência | `PrimeiroDestinoGrupo` | Para onde foi **nesse primeiro movimento** |
| Data da 1ª Transferência para o COI | `DataPrimeiraEntradaNoCOI` | Quando o chamado foi **transferido para o COI** pela primeira vez |
| Aberto por | `RegistradorNome` | **Quem abriu** o chamado |
| Grupo Atual | `GrupoAtual` | Em que fila o chamado está **hoje** |

---

## 3. As três datas

As três colunas de data respondem perguntas diferentes e **não são
intercambiáveis**, mesmo quando mostram o mesmo instante. Todas estão no horário
de Brasília; a base grava em UTC e a consulta converte.

| Nome exibido | Coluna técnica | O que é | De onde vem |
|---|---|---|---|
| Data de Abertura | `DataAbertura` | O instante em que o chamado foi **criado** no SDM, em qualquer fila | `call_req.open_date` |
| Data de Registro no COI | `DataRegistroCOI` | O instante da **primeira entrada** do chamado no COI. É a data que conta o indicador e que o filtro Mês/Ano usa | Calculada pela regra: é a abertura ou a primeira transferência para o COI, conforme a evidência |
| Data da 1ª Transferência para o COI | `DataPrimeiraEntradaNoCOI` | O instante do **primeiro evento de transferência de grupo cujo destino é o COI**, em toda a vida do chamado | Histórico do chamado (`act_log`, eventos de transferência de grupo) |

**Como a Data de Registro no COI é escolhida** (seção 4 de
[`coi-calculation.md`](coi-calculation.md)):

| Código da Evidência | Data de Registro no COI | Data da 1ª Transferência para o COI | Chamados |
|---|---|---|---|
| `AUTOMACAO_TASK_SCHEDULER` | a abertura | vazia | 13.036 |
| `ABERTO_NO_COI_CADEIA` | a abertura | vazia (9.008) ou **posterior** ao registro (932) | 9.940 |
| `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL` e `..._HISTORICO` | a abertura | vazia | 4.485 |
| `JA_ESTAVA_NO_COI_HISTORICO` | a abertura | posterior ao registro | 1 |
| `TRANSFERIDO_PARA_COI` | a 1ª transferência para o COI | **igual** à Data de Registro no COI | 2.056 |
| `ENTRADA_DEMONSTRAVEL_DESTINO` | a 1ª transferência para o COI | **igual** à Data de Registro no COI | 27 |

Como ler:

- **Coluna 8 vazia** é o caso mais comum. O chamado nunca foi transferido para o
  COI: nasceu no COI ou foi registrado pela automação na fila de destino.
- **Coluna 8 igual à coluna 7**: o chamado nasceu em outra fila e entrou no COI
  por transferência. A entrada é essa transferência.
- **Coluna 8 depois da coluna 7**: o chamado nasceu no COI, saiu e foi
  transferido de volta mais tarde. A volta **não** é uma entrada nova: o
  chamado conta uma vez, na primeira entrada, que foi a abertura.
- **Coluna 7 depois da coluna 6**: só acontece quando a entrada foi uma
  transferência. O chamado já existia em outra fila antes de chegar ao COI.

Exemplos:

| SDM | Data de Abertura | Data de Registro no COI | Data da 1ª Transferência para o COI | Leitura |
|---|---|---|---|---|
| 1744024 | 29/10/2026 20:15:56 | 29/10/2026 20:15:56 | 29/10/2026 23:56:48 | Aberto no COI; saiu para `SUPORTE - MT` e voltou às 23:56. Conta na abertura |
| 1744067 | 30/10/2026 09:57:56 | 30/10/2026 12:06:24 | 30/10/2026 12:06:24 | Aberto no `NSTI SO` e transferido para o COI às 12:06. Conta na transferência |
| 1743207 | 28/10/2026 09:00:01 | 28/10/2026 09:00:01 | (vazia) | Registrado pela automação Task Scheduler direto em `Fornecedores - AMM`. Conta na abertura |

O nome técnico `DataPrimeiraEntradaNoCOI` é anterior a este guia e não muda,
porque a consulta e o modelo dependem dele. No painel ele aparece como **Data da
1ª Transferência para o COI**, que descreve o que a coluna guarda. A primeira
entrada no COI, no sentido do indicador, é sempre a **Data de Registro no COI**.

---

## 4. Como o chamado entrou: Forma, Código da Evidência e Tipo de Automação

### Forma de Registro no COI × Código da Evidência

As duas respondem **a mesma pergunta** — por que e quando o chamado entrou no
indicador —, em duas linguagens:

- **Código da Evidência** (`EvidenciaRegistroCOI`) é o rótulo técnico que a regra
  atribui ao chamado, sem tradução. Cada valor está na tabela da seção 4 de
  [`coi-calculation.md`](coi-calculation.md).
- **Forma de Registro no COI** (`FormaRegistroCOI`) é a tradução desse rótulo
  para leitura e filtro.

| Forma de Registro no COI | Código da Evidência | Significado |
|---|---|---|
| Aberto no COI | `ABERTO_NO_COI_CADEIA` | A primeira transferência de grupo sai do COI: o chamado nasceu no COI |
| Já estava no COI histórico | `JA_ESTAVA_NO_COI_HISTORICO` | A primeira transferência sai da fila antiga do COI (`Contrato 7/2023 - COI`) num chamado aberto antes da mudança de contrato |
| Transferido para o COI | `TRANSFERIDO_PARA_COI` | O chamado nasceu em outra fila e foi transferido para o COI |
| Entrada identificada pelo destino | `ENTRADA_DEMONSTRAVEL_DESTINO` | A origem da primeira transferência não prova onde o chamado nasceu, mas há transferência com destino COI |
| Aberto no COI - inferido | `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL` | Nenhuma transferência de grupo em toda a vida, e o grupo atual é o COI |
| Aberto no COI - inferido | `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO` | Nenhuma transferência, o grupo atual é a fila antiga do COI e o chamado abriu antes da mudança de contrato |
| Registrado por automação do COI | `AUTOMACAO_TASK_SCHEDULER` | Registrado pela automação oficial Task Scheduler / SESUC na fila de destino |

A Forma **não substitui** o Código: dois códigos têm o mesmo texto, *Aberto no
COI - inferido*. Para separá-los, use o Código da Evidência. Se a regra ganhar
uma evidência sem tradução, a Forma mostra `Outro - <código>`, nunca vazio.

### Código da Evidência × Tipo de Automação

São informações **independentes**:

- **Código da Evidência**: *por que e quando* o chamado entrou no indicador.
- **Tipo de Automação** (`TipoAutomacaoCOI`): *de onde* veio o registro — qual
  automação criou o chamado, se alguma.

| Tipo de Automação | Quando aparece | Decide se o chamado entra? |
|---|---|---|
| Task Scheduler / SESUC | Criação via interface CMD, por `servicedesk`, com `%GROUP=` de uma fila da lista oficial — os três ao mesmo tempo, no primeiro registro de criação | Sim, mas só como último recurso (abaixo) |
| Zabbix Monitor | Incidente aberto pela conta técnica `usr_automacoes` | Não: só classifica |
| Robo COI | Assinatura técnica do robô no registro de criação (criado via CMD, com duas marcas `%FROM_USERID=` e ao menos uma `%TYPE=`) | Não: só classifica |
| Não automatizado | Nenhuma das três assinaturas | — |

Quando mais de uma assinatura se aplica, vale a primeira nesta ordem: Task
Scheduler, Zabbix, Robo COI. As regras completas estão na seção 5 de
[`coi-calculation.md`](coi-calculation.md).

**Por que um chamado do Task Scheduler pode ter outra evidência.** A regra
consulta primeiro a cadeia real de transferências, depois o histórico, depois o
grupo atual, e só no fim a automação. Se o chamado já entra por uma das
primeiras, a evidência é essa, e o Tipo de Automação continua informando que
ele veio do Task Scheduler. Por isso há 1.957 chamados com Tipo de Automação
*Task Scheduler / SESUC* e evidência diferente de `AUTOMACAO_TASK_SCHEDULER`. Por
exemplo, o SDM 1744189 foi criado pela automação com `%GROUP=COI`, nasceu e ficou
no COI e entra como `ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL`.

Do mesmo modo, chamados do Zabbix e do Robo COI costumam ter a mesma evidência,
`ABERTO_NO_COI_CADEIA`: a evidência não os distingue; o Tipo de Automação sim.

---

## 5. Os quatro grupos

Quatro colunas mostram nomes de fila. Elas falam de **momentos diferentes** da
vida do chamado e **não precisam coincidir**.

| Nome exibido | Coluna técnica | O que é | De onde vem | Sem valor |
|---|---|---|---|---|
| Grupo Informado na Criação | `GrupoInit` | A fila **declarada** pelo programa que criou o chamado, na marca `%GROUP=` do registro de criação. É auxiliar: pode não ser a fila em que o chamado nasceu | Evento de criação (`INIT`) do histórico; havendo mais de um, o mais antigo | `(sem %GROUP= no INIT)` |
| Origem da 1ª Transferência | `PrimeiraOrigemGrupo` | A fila de onde o chamado saiu na **primeira transferência de grupo legível** do histórico. Quando há transferência, é a principal evidência de onde o chamado nasceu | Primeiro evento de transferência de grupo (`TR`) do histórico | `(origem não legível)` |
| Destino da 1ª Transferência | `PrimeiroDestinoGrupo` | A fila para onde o chamado foi nessa **mesma** transferência. Não precisa ser o COI | O mesmo evento | `(sem evento de grupo)` |
| Grupo Atual | `GrupoAtual` | A fila em que o chamado está **hoje**, no cadastro do chamado | `call_req.group_id`, com o nome do grupo em `ca_contact` | `(não resolvido)` |

Como ler:

- **Grupo Informado na Criação diferente da Origem não é erro.** O programa de
  criação informou um valor e o chamado nasceu em outra fila. A entrada no
  indicador é decidida pela cadeia de transferências; a marca `%GROUP=` só
  decide no critério da automação Task Scheduler.
- **Origem e Destino descrevem a primeira transferência de grupo, não a primeira
  transferência para o COI.** No SDM 1743965, a primeira transferência foi de
  `SUPERVISÃO DE SUPORTE TELEFÔNICO` para `SUPERVISÃO DE CHAMADOS`; a
  transferência para o COI veio depois, e é ela que dá a Data de Registro no COI.
- **Sem nenhuma transferência de grupo legível**, Origem mostra
  `(origem não legível)` e Destino mostra `(sem evento de grupo)`. É o caso de
  17.488 dos 29.545 chamados, em geral nascidos e mantidos numa só fila, como os
  registrados pela automação na fila de destino. Nesses casos a regra usa o grupo
  atual ou a automação.
- **Grupo Atual muda com o tempo.** Ele mostra onde o chamado está agora, não
  onde estava quando entrou no COI. Um chamado registrado pelo COI e enviado a
  outra fila aparece com o grupo dessa outra fila.
- **Grafia.** Grupo Informado na Criação, Origem e Destino saem normalizados em
  maiúsculas (`FORNECEDORES - AMM`); Grupo Atual traz o nome como está no
  cadastro (`Fornecedores - AMM`). É a mesma fila.

Exemplo da documentação de cálculo — SDM 1658863: Grupo Informado na Criação
`VIRTUAL TI.ELABORAR/MANTER DOCUMENTAÇÃO` (o nome de uma categoria, informado na
criação), Origem `COI`, Destino `FORNECEDORES - VIRTUAL`. O chamado nasceu no COI
e entra como `ABERTO_NO_COI_CADEIA`, datado na abertura.

---

## 6. Aberto por não é o responsável

**Aberto por** (`RegistradorNome`) é **quem abriu** o chamado: a conta gravada em
`call_req.log_agent`, com o nome de `ca_contact`. Ela não decide nada na regra e
serve para auditoria.

- **Não é quem trouxe o chamado para o COI.** Num chamado transferido para o
  COI, quem abriu é alguém de outra fila.
- **Não é o responsável atual.** O responsável é o analista atribuído ao chamado
  (`call_req.assignee`). Ele aparece como **Responsável** na tabela de
  Encerrados e é o critério de Encerrados da página Por Membro. A tabela de
  Registrados não tem coluna de responsável.
- **Contas técnicas** aparecem quando o chamado foi aberto por automação — por
  exemplo, `Usuário de Serviço - ServiceDesk`, `usr_automacoes` e
  `Sesuc Automação`. A página Por Membro agrupa contas como essas em *Conta
  técnica / automação*.

Valores entre parênteses indicam que o nome não pôde ser obtido:
`(sem registrador no chamado)`, `(UUID sem contato em ca_contact)` e
`(contato sem nome)`.

---

## 7. Por que aparecem filas de fornecedor ou do NSTI

Um chamado **registrado pelo COI** pode mostrar `FORNECEDORES - AMM`, `NSTI BD`
ou outra fila externa em Grupo Informado na Criação, Destino ou Grupo Atual. Há
dois motivos, e nenhum é erro:

1. **A automação oficial registra direto na fila de destino.** O Task Scheduler /
   SESUC cria chamados em nome do COI já na fila do NSTI ou do fornecedor, sem
   passar pela fila do COI. Por isso a fila da marca `%GROUP=` é externa, não há
   transferência de grupo e o Grupo Atual costuma ser essa mesma fila. O chamado
   entra pela regra da automação (seção 5 de
   [`coi-calculation.md`](coi-calculation.md)), com Data de Registro no COI na
   abertura. Essa evidência não afirma que o chamado passou pelo COI: afirma que
   o COI o registrou por automação oficial.

   Exemplo — SDM 1743207: Grupo Informado na Criação `FORNECEDORES - AMM`; Origem
   `(origem não legível)`; Destino `(sem evento de grupo)`; Grupo Atual
   `Fornecedores - AMM`; Forma *Registrado por automação do COI*; Código
   `AUTOMACAO_TASK_SCHEDULER`; Tipo de Automação *Task Scheduler / SESUC*; Aberto
   por `Usuário de Serviço - ServiceDesk`.

2. **O COI registra e encaminha.** Um chamado aberto no COI é transferido para a
   fila que vai atendê-lo. A Origem da 1ª Transferência é `COI` e o Destino é a
   fila seguinte — por exemplo, `COI` → `FORNECEDORES - A2B` (779 chamados) ou
   `COI` → `NSTI SEGURANÇA` (1.492). O Grupo Atual mostra onde o chamado está
   hoje.

*Registrado pelo COI* quer dizer que o chamado **entrou** no COI, ou foi
registrado por ele, no período. Não quer dizer que ele está no COI hoje, nem
que o COI o atendeu.

---

## 8. Valores especiais

| Valor | Coluna | Significado |
|---|---|---|
| `(sem %GROUP= no INIT)` | Grupo Informado na Criação | O registro de criação não traz a marca `%GROUP=` |
| `(origem não legível)` | Origem da 1ª Transferência | Não há transferência de grupo legível, ou a origem dela está em branco |
| `(sem evento de grupo)` | Destino da 1ª Transferência | O chamado não tem transferência de grupo legível no histórico |
| `(não resolvido)` | Grupo Atual | O grupo do chamado não tem nome no cadastro |
| *(vazia)* | Data da 1ª Transferência para o COI | O chamado nunca foi transferido para o COI |
| `Não automatizado` | Tipo de Automação | Nenhuma das três assinaturas de automação |
| `Outro - <código>` | Forma de Registro no COI | Evidência sem tradução (não ocorre hoje) |

---

## 9. Colunas do modelo que não estão na tabela

A tabela `Chamados Registrados` do modelo tem 30 colunas; a tabela da Visão
Geral exibe 16. As demais continuam no modelo, com o nome técnico, para
auditoria e para as medidas: `DataRegistro`, `HoraRegistro`, `TipoCodigo`,
`RegistradorUUID`, `RegistradorUserID`, `AliasEvidencia`,
`DataPrimeiroEventoGrupo`, `QtdEventosGrupo`, `QtdAncorasGrupo`,
`QtdAncorasAntesDo1oLegivel`, `UUIDGrupoAtual`,
`InitConsistenteComReconstrucao`, `AbertoAntesDoPeriodo` e `Anomalia`. A
descrição delas está na seção 10 de [`coi-calculation.md`](coi-calculation.md).
