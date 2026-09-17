# Extração de dados — COI

Repositório com consultas SQL, documentações e arquivos de validação usados para mensurar a volumetria e a auditoria do **COI** a partir da base do **CA Service Desk Manager**.

O objetivo do projeto é manter, em um só lugar, as consultas usadas para identificar chamados registrados e encerrados pelo COI, a explicação das regras aplicadas e os materiais de conferência contra os relatórios recebidos.

## Estrutura do repositório

```text
.
├── coi/
│   ├── queries/
│   │   ├── consulta_coi_encerrados.sql
│   │   ├── consulta_coi_pesquisa_satisfacao_encerrados.sql
│   │   ├── consulta_coi_registrados_detalhe.sql
│   │   ├── consulta_coi_registrados_encerrados_diario.sql
│   │   ├── consulta_coi_registrados_membros.sql
│   │   ├── consulta_coi_registrados_mensal.sql
│   │   ├── consulta_coi_registrados_por_evidencia.sql
│   │   ├── consulta_coi_registrados_por_hora.sql
│   │   ├── consulta_coi_registrados_por_registrador.sql
│   │   ├── consulta_coi_registrados_total_com_tecnicos.sql
│   │   ├── consulta_coi_registrados_universo_bruto.sql
│   │   └── consulta_coi_registrados_validacao.sql
│   ├── powerbi/
│   │   └── consulta_coi_volumetria_power_bi.sql
│   └── docs/
│       └── project-context/
│           └── histórico e contexto do projeto
│
├── docs/
│   └── project-context/
│       └── histórico e contexto do projeto
│
├── support/
│   ├── consulta_logs_chamados_listados.sql
│   ├── consulta_status_chamados.sql
│   ├── consulta_status_hold.sql
│   └── consulta_tipos_chamado.sql
│
├── LICENSE
├── README.md
└── .git/
```

## O que é o COI

O COI não tem FAIA nem FARC. A demanda é de **volumetria**: quantos chamados entram, quantos saem e em que horário.

A regra de negócio é construída a partir do histórico de fila, do tipo de chamado e da evidência de passagem pelo COI. O objetivo é manter uma base consistente para comparar a apuração com os relatórios do fornecedor e com o painel.

## Consultas principais

### Registrados pelo COI

O bloco de consultas de registrados responde à pergunta: **quais chamados efetivamente entraram na base do COI no período**.

**Indicadores** — o que alimenta gráfico e painel:

| Arquivo | Indicador | Saída |
|---|---|---|
| [`coi/queries/consulta_coi_registrados_mensal.sql`](coi/queries/consulta_coi_registrados_mensal.sql) | Registrados por mês, separando Incidentes e Solicitações | `Ano, Mes, MesAno, Incidentes, Solicitacoes, Total` |
| [`coi/queries/consulta_coi_registrados_encerrados_diario.sql`](coi/queries/consulta_coi_registrados_encerrados_diario.sql) | Registrados × Encerrados por dia (I e R juntos) | `Dia, Registrados, Encerrados` |
| [`coi/queries/consulta_coi_registrados_por_hora.sql`](coi/queries/consulta_coi_registrados_por_hora.sql) | Registrados por hora, dias consolidados | `Ano, Mes, MesAno, Hora, HoraLabel, QtdRegistrados` |

**Auditoria** — a mesma população, por outros ângulos, para provar o número:

| Arquivo | Para que serve |
|---|---|
| [`coi/queries/consulta_coi_registrados_detalhe.sql`](coi/queries/consulta_coi_registrados_detalhe.sql) | **Uma linha por SDM**: data/hora do registro, tipo, quem registrou, grupo atual, evidência e data da primeira entrada na fila |
| [`coi/queries/consulta_coi_registrados_por_registrador.sql`](coi/queries/consulta_coi_registrados_por_registrador.sql) | A mesma população agrupada por quem registrou (`log_agent`) |
| [`coi/queries/consulta_coi_registrados_por_evidencia.sql`](coi/queries/consulta_coi_registrados_por_evidencia.sql) | Composição do total por classe de evidência |
| [`coi/queries/consulta_coi_registrados_validacao.sql`](coi/queries/consulta_coi_registrados_validacao.sql) | Uma linha de sanidade com validações automáticas |

### Encerrados pelo COI

Diferente das consultas acima, [`coi/queries/consulta_coi_encerrados.sql`](coi/queries/consulta_coi_encerrados.sql) não conta: ela **lista**. Devolve **uma linha por SDM** encerrado pelo COI, para conferência caso a caso.

A regra é a seguinte: um chamado é considerado encerrado pelo COI quando:

1. o fechamento cai no período analisado;
2. o tipo é `I` (Incidente) ou `R` (Solicitação);
3. o status é `CL` ou `CLUNRSLV`;
4. o grupo atual do chamado é o grupo alvo da apuração.

O período é parametrizável, com intervalo semiaberto (`>= início` e `< fim`), e a identidade do grupo é definida por UUID, não por nome.

### Painel

Para o painel existe [`coi/powerbi/consulta_coi_volumetria_power_bi.sql`](coi/powerbi/consulta_coi_volumetria_power_bi.sql), que entrega os indicadores em um único result set discriminado pela coluna `TipoResultado`.

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
3. Mantenha `@MostrarDiagnostico = 0` para uso normal.
4. Execute a consulta na base `mdb`.
5. Exporte o resultado.
6. Compare com os arquivos recebidos do fornecedor.
7. Salve a análise na pasta de validação correspondente.

Quando houver divergência, use `@MostrarDiagnostico = 1` para retornar tabelas de conferência.

## Parâmetros comuns

As consultas normalmente possuem parâmetros como:

```sql
DECLARE @InicioBrasil datetime2(0)
DECLARE @FimBrasil    datetime2(0)
DECLARE @MostrarDiagnostico bit = 0
```

- `@InicioBrasil` e `@FimBrasil` definem o período analisado.
- `@MostrarDiagnostico = 0` retorna apenas o resultado final.
- `@MostrarDiagnostico = 1` retorna informações extras para investigação.

## Fluxo de validação

O fluxo esperado é:

```text
consulta SQL → resultado exportado → comparação com relatório do fornecedor → análise e reconciliação → ajuste ou confirmação da regra
```

As consultas de auditoria servem para confirmar a população e validar se os totais estão consistentes com a regra vigente.

## Convenções do projeto

- `coi/queries/`: consultas executáveis relacionadas ao COI.
- `coi/powerbi/`: consultas de painel e consolidação.
- `support/`: consultas auxiliares.
- `docs/`: histórico, contexto e material de apoio.

Ao alterar uma regra de cálculo, atualize também a documentação correspondente e valide o impacto nos indicadores e no painel.
