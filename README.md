# Extração de dados — COI

Repositório com consultas SQL, documentações e arquivos de validação usados para mensurar a volumetria e a auditoria do **COI** a partir da base do **CA Service Desk Manager**.

O objetivo do projeto é manter, em um só lugar, as consultas usadas para identificar chamados registrados e encerrados pelo COI, a explicação das regras aplicadas e os materiais de conferência contra os relatórios recebidos.

Este repositório atende **somente o COI**. Decision e A2B/Protect4 têm repositórios próprios (`Extracao_de_dados_Decision` e `Extracao_de_dados_A2B`) e nada deles vive aqui.

## Estrutura do repositório

```text
.
├── queries/                                  16 consultas de referência (fonte de verdade)
│   ├── consulta_coi_encerrados.sql                               painel
│   ├── consulta_coi_encerrados_por_hora.sql
│   ├── consulta_coi_pesquisa_satisfacao_encerrados.sql
│   ├── consulta_coi_pesquisa_satisfacao_encerrados_detalhe.sql   painel
│   ├── consulta_coi_registrados_detalhe.sql                      painel
│   ├── consulta_coi_registrados_encerrados_diario.sql            painel
│   ├── consulta_coi_registrados_encerrados_por_hora.sql          painel
│   ├── consulta_coi_registrados_encerrados_por_membro.sql        painel
│   ├── consulta_coi_registrados_membros.sql
│   ├── consulta_coi_registrados_mensal.sql
│   ├── consulta_coi_registrados_por_evidencia.sql
│   ├── consulta_coi_registrados_por_hora.sql
│   ├── consulta_coi_registrados_por_registrador.sql
│   ├── consulta_coi_registrados_total_com_tecnicos.sql
│   ├── consulta_coi_registrados_universo_bruto.sql
│   └── consulta_coi_registrados_validacao.sql
├── powerbi/
│   ├── <consulta de queries/>_power_bi.sql   6 arquivos: as consultas marcadas painel acima
│   ├── powerbi-query.md                   documentação das consultas do Power BI
│   └── documentacao-powerbi-coi.html      conteúdo da página Documentação do painel
├── docs/
│   ├── coi-calculation.md                 regras de cálculo, a partir de queries/
│   └── coi-registrados-colunas.md         guia de leitura das colunas de Registrados
├── project-context/
│   └── COI-HISTORICO-CONTEXTO-MESTRE.md   Histórico Mestre do COI
├── support/
│   ├── consulta_logs_chamados_listados.sql
│   ├── consulta_status_chamados.sql
│   ├── consulta_status_hold.sql
│   └── consulta_tipos_chamado.sql
├── README.md
└── .git/
```

## O que é o COI

O COI não tem FAIA nem FARC. A demanda é de **volumetria**: quantos chamados entram, quantos saem e em que horário.

A regra de negócio é construída a partir do histórico de fila, do tipo de chamado e da evidência de passagem pelo COI. O objetivo é manter uma base consistente para comparar a apuração com os relatórios do fornecedor e com o painel.

## Consultas principais

### Registrados pelo COI

O bloco de consultas de registrados responde à pergunta: **quais chamados efetivamente entraram na base do COI no período**.

Um chamado entra por evidência de passagem pela fila COI (cadeia real de grupo, histórico, fallback de grupo atual) **ou** por registro da automação oficial Task Scheduler / SESUC, que registra direto na fila do NSTI ou do fornecedor. As nove consultas que contam Registrados (as sete abaixo e as de Registrados × Encerrados por membro e por hora) e as quatro versões do Power BI que as usam compartilham um **bloco canônico** idêntico, conferido por SHA256. A regra está descrita em [`docs/coi-calculation.md`](docs/coi-calculation.md); a precedência e o hash vigente estão no Histórico Mestre.

**Indicadores**:

| Arquivo | Indicador | Saída |
|---|---|---|
| [`queries/consulta_coi_registrados_mensal.sql`](queries/consulta_coi_registrados_mensal.sql) | Registrados por mês, separando Incidentes e Solicitações | `Ano, Mes, MesAno, Incidentes, Solicitacoes, Total` |
| [`queries/consulta_coi_registrados_encerrados_diario.sql`](queries/consulta_coi_registrados_encerrados_diario.sql) | Registrados × Encerrados por dia (I e R juntos) | `Dia, Registrados, Encerrados` |
| [`queries/consulta_coi_registrados_por_hora.sql`](queries/consulta_coi_registrados_por_hora.sql) | Registrados por hora, dias consolidados (referência; o painel usa a consulta abaixo) | `Ano, Mes, MesAno, Hora, HoraLabel, QtdRegistrados` |
| [`queries/consulta_coi_registrados_encerrados_por_hora.sql`](queries/consulta_coi_registrados_encerrados_por_hora.sql) | Registrados × Encerrados por hora, dias consolidados, 24 horas por mês — cada série com a sua regra e a sua hora | `Ano, Mes, MesAno, Hora, HoraLabel, Registrados, Encerrados` |
| [`queries/consulta_coi_registrados_encerrados_por_membro.sql`](queries/consulta_coi_registrados_encerrados_por_membro.sql) | Registrados (por quem abriu) e Encerrados de cada conta, por mês. O painel usa `EncerradosComoResponsavel` — o responsável pelo chamado, critério do fornecedor; `Encerrados` (quem executou o encerramento) fica para auditoria | `Ano, Mes, MesAno, MembroUUID, MembroUserID, Membro, TipoConta, Registrados, Encerrados, EncerradosComoResponsavel` |

**Auditoria** — a mesma população, por outros ângulos, para provar o número:

| Arquivo | Para que serve |
|---|---|
| [`queries/consulta_coi_registrados_detalhe.sql`](queries/consulta_coi_registrados_detalhe.sql) | **Uma linha por SDM**: categoria, resumo, item de configuração, data/hora do registro, tipo, quem abriu, grupos, evidência, automação e data da primeira transferência para o COI. O que cada coluna significa está em [`docs/coi-registrados-colunas.md`](docs/coi-registrados-colunas.md) |
| [`queries/consulta_coi_registrados_por_registrador.sql`](queries/consulta_coi_registrados_por_registrador.sql) | A mesma população agrupada por quem registrou (`log_agent`) |
| [`queries/consulta_coi_registrados_por_evidencia.sql`](queries/consulta_coi_registrados_por_evidencia.sql) | Composição do total por classe de evidência |
| [`queries/consulta_coi_registrados_validacao.sql`](queries/consulta_coi_registrados_validacao.sql) | Uma linha de sanidade com validações automáticas |

### Encerrados pelo COI

Diferente das consultas acima, [`queries/consulta_coi_encerrados.sql`](queries/consulta_coi_encerrados.sql) não conta: ela **lista**. Devolve **uma linha por SDM** encerrado pelo COI, para conferência caso a caso.

A regra é a seguinte: um chamado é considerado encerrado pelo COI quando:

1. o fechamento cai no período analisado;
2. o tipo é `I` (Incidente) ou `R` (Solicitação);
3. o status é `CL` ou `CLUNRSLV`;
4. o grupo atual do chamado é o grupo alvo da apuração.

O período é parametrizável, com intervalo semiaberto (`>= início` e `< fim`), e a identidade do grupo é definida por UUID, não por nome.

Com a mesma população e a mesma conferência do grupo alvo:

| Arquivo | Para que serve |
|---|---|
| [`queries/consulta_coi_encerrados_por_hora.sql`](queries/consulta_coi_encerrados_por_hora.sql) | Encerrados por hora do fechamento, 24 horas por mês: `Ano, Mes, MesAno, Hora, HoraLabel, QtdEncerrados` (referência; o painel usa Registrados × Encerrados por hora) |
| [`queries/consulta_coi_pesquisa_satisfacao_encerrados.sql`](queries/consulta_coi_pesquisa_satisfacao_encerrados.sql) | Pesquisa de satisfação: resumo (Janela 1), respostas (Janela 2) e conferência |
| [`queries/consulta_coi_pesquisa_satisfacao_encerrados_detalhe.sql`](queries/consulta_coi_pesquisa_satisfacao_encerrados_detalhe.sql) | A mesma classificação, uma linha por chamado encerrado, com data e o pedido de pesquisa registrado no SDM |

### Painel

O painel tem sete páginas: **Início** (navegação e última atualização), **Visão Geral**, **Movimentação de Chamados** (no menu, *Movimentação*: distribuição por dia do mês e por hora do dia), **Por Membro**, **Por Tipo**, **Satisfação** e **Documentação**. O projeto do Power BI (`painel-coi.pbip`: modelo, relatório e os fundos das páginas, exportados do Figma) é mantido **fora deste repositório**; aqui ficam as consultas SQL que ele usa e a documentação. A montagem das páginas está na seção 6 de [`powerbi/powerbi-query.md`](powerbi/powerbi-query.md).

A pasta `powerbi/` tem **só as 6 consultas que o painel usa**, cada uma com o nome da sua referência em `queries/` acrescido de `_power_bi`:

| Consulta do Power BI | Páginas |
|---|---|
| `consulta_coi_registrados_detalhe_power_bi.sql` | Visão Geral, Por Tipo |
| `consulta_coi_encerrados_power_bi.sql` | Visão Geral, Por Tipo |
| `consulta_coi_registrados_encerrados_diario_power_bi.sql` | Visão Geral, Movimentação de Chamados (modalidade Por dia) |
| `consulta_coi_registrados_encerrados_por_hora_power_bi.sql` | Movimentação de Chamados (modalidade Por hora) |
| `consulta_coi_registrados_encerrados_por_membro_power_bi.sql` | Por Membro |
| `consulta_coi_pesquisa_satisfacao_encerrados_detalhe_power_bi.sql` | Satisfação |

Cada uma aplica a mesma regra da sua referência, com período automático (os últimos meses completos, quantos o parâmetro `QtdMesesCompletosCOI` do Power Query indicar — 12 por padrão —, nunca antes de março de 2026) e um único resultado. As demais consultas de `queries/` — mensal, por evidência, por registrador, validação, membros, contas técnicas, universo bruto, o resumo da satisfação e as duas por hora separadas — servem à referência, à validação e à conciliação com o fornecedor, e não alimentam o painel.

A documentação das consultas do Power BI está em [`powerbi/powerbi-query.md`](powerbi/powerbi-query.md). O conteúdo da página Documentação, para o visual HTML Content, está em [`powerbi/documentacao-powerbi-coi.html`](powerbi/documentacao-powerbi-coi.html).

As tabelas de chamados da Visão Geral exibem nomes de leitura (por exemplo, `DataRegistroCOI` aparece como **Data de Registro no COI**), trocados só no visual: no SQL e no modelo as colunas mantêm o nome técnico. A correspondência entre os nomes e a explicação de cada coluna de Registrados — as três datas, evidência, automação, os quatro grupos e quem abriu — estão em [`docs/coi-registrados-colunas.md`](docs/coi-registrados-colunas.md).

## Consultas de apoio

A pasta `support/` contém consultas auxiliares usadas durante análise e depuração.

| Arquivo | Uso |
|---|---|
| `support/consulta_logs_chamados_listados.sql` | Lista todos os logs dos chamados informados |
| `support/consulta_status_chamados.sql` | Lista os status cadastrados no SDM |
| `support/consulta_status_hold.sql` | Mostra cada status e o flag `cr_stat.hold`, que indica se ele para o relógio do SLA |
| `support/consulta_tipos_chamado.sql` | Lista os tipos de chamado e suas quantidades |

Essas consultas não calculam indicadores do COI. Elas servem para investigar chamados, conferir códigos e entender registros da base.

## Como usar as consultas

1. Abra o arquivo SQL do indicador desejado.
2. Ajuste o período de apuração nos parâmetros de data.
3. Execute o arquivo **inteiro** na base `mdb`, sem selecionar trecho.
4. Exporte o resultado.
5. Compare com os arquivos recebidos do fornecedor.

Para conferir a regra de Registrados num período, rode `consulta_coi_registrados_validacao.sql`: todas as asserções devem voltar `SIM`.

## Parâmetros comuns

Os nomes variam por família de consulta:

| Consultas | Início (inclusivo) | Fim (exclusivo) | Conferência |
|---|---|---|---|
| Registrados (`consulta_coi_registrados_*.sql`) | `@InicioBR` | `@FimBR` | `@MostrarDiagnostico` no por membro |
| Encerrados e Encerrados por hora | `@DataInicio` | `@DataFim` | `@MostrarDiagnostico` em Encerrados |
| Pesquisa de satisfação dos encerrados (resumo e detalhe) | `@DataInicio` | `@DataFim` | `@MostrarConferencia` no resumo |
| Power BI (`powerbi/*_power_bi.sql`) | automático: `@PBI_QuantidadeMeses` meses antes do fim — no Power BI, o valor do parâmetro `QtdMesesCompletosCOI` (padrão 12); fora dele, 12 —, nunca antes de `@PBI_InicioMinimoBR` (01/03/2026) | dia 1 do mês corrente | as da referência |

- Todas as datas são horário do Brasil (GMT-3) e o intervalo é **semiaberto**: `>= início` e `< fim`. Para março inteiro, use início `2026-03-01 00:00:00` e fim `2026-04-01 00:00:00` — nunca `23:59:59`.
- `@TransIniBR` e `@TransFimBR`, dentro do bloco canônico, marcam a janela da renomeação das filas do COI em 18/03/2026. **Não são parâmetros de período** e não devem ser alterados.

## Fluxo de validação

O fluxo esperado é:

```text
consulta SQL → resultado exportado → comparação com relatório do fornecedor → análise e reconciliação → ajuste ou confirmação da regra
```

As consultas de auditoria servem para confirmar a população e validar se os totais estão consistentes com a regra vigente.

## Convenções do projeto

- `queries/`: consultas executáveis relacionadas ao COI.
- `powerbi/`: só as consultas que o painel usa, e a sua documentação.
- `support/`: consultas auxiliares.
- `project-context/`: Histórico Mestre do COI.

Ao alterar uma regra de cálculo, atualize também a documentação correspondente e valide o impacto nos indicadores e no painel.

## Histórico Mestre

O histórico do projeto fica em
[`project-context/COI-HISTORICO-CONTEXTO-MESTRE.md`](project-context/COI-HISTORICO-CONTEXTO-MESTRE.md).

- Ele é **append-only**: cada intervenção vira uma seção nova, e seções antigas não são reescritas.
- Trabalhos do COI atualizam **somente** este histórico. Decision e A2B mantêm o seu, nos respectivos repositórios.
- As seções anteriores à separação dos repositórios foram herdadas do documento compartilhado da época em que os três núcleos viviam em `Queries`. Elas contêm registros de Decision e Protect4 e são mantidas como **legado histórico**, sem reescrita. Caminhos citados nelas (`coi/queries/`, `docs/project-context/`, …) descrevem a estrutura da época.
- Alguns comentários de cabeçalho das consultas citam caminhos antigos. Eles fazem parte do bloco canônico, conferido por SHA256, e por isso não acompanham mudanças de pasta; os arquivos ficam em `queries/` e `powerbi/`.
