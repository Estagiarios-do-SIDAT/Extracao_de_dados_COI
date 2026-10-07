# Extração de dados — COI

Repositório com consultas SQL, documentações e arquivos de validação usados para mensurar a volumetria e a auditoria do **COI** a partir da base do **CA Service Desk Manager**.

O objetivo do projeto é manter, em um só lugar, as consultas usadas para identificar chamados registrados e encerrados pelo COI, a explicação das regras aplicadas e os materiais de conferência contra os relatórios recebidos.

Este repositório atende **somente o COI**. Decision e A2B/Protect4 têm repositórios próprios (`Extracao_de_dados_Decision` e `Extracao_de_dados_A2B`) e nada deles vive aqui.

## Estrutura do repositório

```text
.
├── queries/
│   ├── consulta_coi_encerrados.sql
│   ├── consulta_coi_pesquisa_satisfacao_encerrados.sql
│   ├── consulta_coi_registrados_detalhe.sql
│   ├── consulta_coi_registrados_encerrados_diario.sql
│   ├── consulta_coi_registrados_membros.sql
│   ├── consulta_coi_registrados_mensal.sql
│   ├── consulta_coi_registrados_por_evidencia.sql
│   ├── consulta_coi_registrados_por_hora.sql
│   ├── consulta_coi_registrados_por_registrador.sql
│   ├── consulta_coi_registrados_total_com_tecnicos.sql
│   ├── consulta_coi_registrados_universo_bruto.sql
│   └── consulta_coi_registrados_validacao.sql
├── powerbi/
│   └── <consulta de queries/>_power_bi.sql   12 arquivos, um por consulta
├── docs/
│   ├── coi-calculation.md                 regras de cálculo, a partir de queries/
│   ├── powerbi-query.md                   documentação das consultas do Power BI
│   ├── documentacao-powerbi-coi.html      versão resumida para o Power BI
│   └── feriados.txt                       calendário comum de feriados do TCU (cópia; não usado pelas consultas do COI)
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

Um chamado entra por evidência de passagem pela fila COI (cadeia real de grupo, histórico, fallback de grupo atual) **ou** por registro da automação oficial Task Scheduler / SESUC, que registra direto na fila do NSTI ou do fornecedor. As sete consultas e as suas sete versões do Power BI compartilham um **bloco canônico** idêntico, conferido por SHA256. A regra está descrita em [`docs/coi-calculation.md`](docs/coi-calculation.md); a precedência e o hash vigente estão no Histórico Mestre.

**Indicadores** — o que alimenta gráfico e painel:

| Arquivo | Indicador | Saída |
|---|---|---|
| [`queries/consulta_coi_registrados_mensal.sql`](queries/consulta_coi_registrados_mensal.sql) | Registrados por mês, separando Incidentes e Solicitações | `Ano, Mes, MesAno, Incidentes, Solicitacoes, Total` |
| [`queries/consulta_coi_registrados_encerrados_diario.sql`](queries/consulta_coi_registrados_encerrados_diario.sql) | Registrados × Encerrados por dia (I e R juntos) | `Dia, Registrados, Encerrados` |
| [`queries/consulta_coi_registrados_por_hora.sql`](queries/consulta_coi_registrados_por_hora.sql) | Registrados por hora, dias consolidados | `Ano, Mes, MesAno, Hora, HoraLabel, QtdRegistrados` |

**Auditoria** — a mesma população, por outros ângulos, para provar o número:

| Arquivo | Para que serve |
|---|---|
| [`queries/consulta_coi_registrados_detalhe.sql`](queries/consulta_coi_registrados_detalhe.sql) | **Uma linha por SDM**: data/hora do registro, tipo, quem registrou, grupo atual, evidência e data da primeira entrada na fila |
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

### Painel

A pasta `powerbi/` tem uma versão para cada uma das 12 consultas de `queries/`, com o mesmo nome acrescido de `_power_bi`. Cada uma aplica a mesma regra da sua referência, com período automático e saída num único resultado.

A documentação das consultas do Power BI está em [`docs/powerbi-query.md`](docs/powerbi-query.md). Uma versão resumida, para o visual HTML Content do Power BI, está em [`docs/documentacao-powerbi-coi.html`](docs/documentacao-powerbi-coi.html).

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
| Registrados (`consulta_coi_registrados_*.sql`) | `@InicioBR` | `@FimBR` | — |
| Encerrados | `@DataInicio` | `@DataFim` | `@MostrarDiagnostico` |
| Pesquisa de satisfação dos encerrados | `@DataInicio` | `@DataFim` | `@MostrarConferencia` |
| Power BI (`powerbi/*_power_bi.sql`) | automático, por `@PBI_QuantidadeMeses`; fixo em membros, contas técnicas e universo bruto | automático; fixo nas mesmas três | as da referência |

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
- `powerbi/`: consultas de painel e consolidação.
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
