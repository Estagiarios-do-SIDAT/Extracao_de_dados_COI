# Consultas do Power BI — COI

Este documento explica como funcionam as consultas que alimentam o Power BI do
COI: o que cada uma entrega, como o período é calculado, como a saída é montada
e como conferir o resultado depois de uma atualização.

São **12 consultas**, uma para cada consulta de referência do COI. Cada consulta
do Power BI aplica **a mesma regra** da sua referência; muda apenas o que é
necessário para o uso no painel. O texto SQL de cada uma fica incorporado ao
relatório, no campo **Instrução SQL** da conexão.

As regras de cálculo — quem conta como Registrado, quem conta como Encerrado, de
onde vem cada data — estão descritas na documentação de cálculo do COI,
`docs/coi-calculation.md`. Este documento trata do que é próprio do Power BI.

---

## Índice

1. [As 12 consultas](#1-as-12-consultas)
2. [Período automático](#2-período-automático)
3. [Saída](#3-saída)
4. [Grupo alvo de Encerrados](#4-grupo-alvo-de-encerrados)
5. [Colunas de diagnóstico do detalhe](#5-colunas-de-diagnóstico-do-detalhe)
6. [Montagem dos gráficos](#6-montagem-dos-gráficos)
7. [Manutenção no Power Query](#7-manutenção-no-power-query)
8. [Conferência depois de atualizar](#8-conferência-depois-de-atualizar)
9. [Limitações](#9-limitações)
10. [Alertas de manutenção](#10-alertas-de-manutenção)

Há uma versão resumida desta documentação em HTML, para exibir dentro do painel
no visual **HTML Content**: `powerbi/documentacao-powerbi-coi.html`. Ela deriva
deste arquivo; se os dois divergirem, **vale este**.

---

## 1. As 12 consultas

Todas ficam em `powerbi/` e têm o nome da consulta de referência seguido de
`_power_bi`.

### Registrados

| Consulta do Power BI | Finalidade | Período | Saída |
|---|---|---|---|
| `consulta_coi_registrados_mensal_power_bi.sql` | Registrados por mês, Incidentes × Solicitações | automático | 1 resultado: `Ano`, `Mes`, `MesAno`, `Incidentes`, `Solicitacoes`, `Total` |
| `consulta_coi_registrados_encerrados_diario_power_bi.sql` | Registrados × Encerrados por dia | automático | 1 resultado: `Dia`, `Registrados`, `Encerrados` |
| `consulta_coi_registrados_por_hora_power_bi.sql` | Registrados por hora do dia, mês a mês | automático | 1 resultado: `Ano`, `Mes`, `MesAno`, `Hora`, `HoraLabel`, `QtdRegistrados` |
| `consulta_coi_registrados_detalhe_power_bi.sql` | Uma linha por SDM registrado, com a evidência e os dados da cadeia | automático | 1 resultado, 27 colunas |
| `consulta_coi_registrados_por_evidencia_power_bi.sql` | Composição dos Registrados por evidência, e as ressalvas | automático | 1 resultado, 7 colunas |
| `consulta_coi_registrados_por_registrador_power_bi.sql` | Registrados agrupados por quem abriu o chamado | automático | 1 resultado, 14 colunas |
| `consulta_coi_registrados_validacao_power_bi.sql` | Sanidade da regra: totais, 16 asserções, consistência, casos de referência e ressalvas | automático | resultados empilhados |

### Encerrados

| Consulta do Power BI | Finalidade | Período | Saída |
|---|---|---|---|
| `consulta_coi_encerrados_power_bi.sql` | Uma linha por SDM encerrado pelo COI | automático | 1 resultado, 14 colunas |
| `consulta_coi_pesquisa_satisfacao_encerrados_power_bi.sql` | Pesquisa de satisfação dos Encerrados | automático | resultados empilhados |

### Conciliação com os relatórios do fornecedor

| Consulta do Power BI | Finalidade | Período | Saída |
|---|---|---|---|
| `consulta_coi_registrados_membros_power_bi.sql` | Chamados abertos por analistas do COI | fixo | resultados empilhados |
| `consulta_coi_registrados_total_com_tecnicos_power_bi.sql` | Membros mais contas técnicas com origem no COI comprovada | fixo | resultados empilhados |
| `consulta_coi_registrados_universo_bruto_power_bi.sql` | Todos os chamados das contas técnicas, classificados | fixo | resultados empilhados |

As consultas de Registrados usam a regra de primeira entrada no COI e a
`DataRegistroCOI`. As de conciliação usam outro modelo, por data de abertura e
por quem abriu, e **não são comparáveis** com as de Registrados.

**Equivalência conferida:** para o mesmo período, cada consulta do Power BI
devolve exatamente o resultado da sua consulta de referência — mesmas colunas,
mesmas linhas, mesmos valores — e duas execuções seguidas dão o mesmo resultado.

---

## 2. Período automático

Nas consultas marcadas como **automático**, o período é calculado a cada
atualização:

| Limite | Valor |
|---|---|
| Fim (exclusivo) | dia 1 do mês corrente, 00:00:00, horário de Brasília |
| Início (inclusivo) | `@PBI_QuantidadeMeses` meses antes do fim |

`@PBI_QuantidadeMeses` vale **6**. Entram **só meses completos**: o mês em
andamento fica de fora. Por exemplo, numa atualização feita em qualquer dia de
setembro de 2026, o período vai de 01/03/2026 a 01/09/2026, e os seis meses
aparecem inteiros.

É a mesma forma de período das consultas de referência, que recebem início e fim
em meses de calendário com fim exclusivo. Para mudar a cobertura, altere apenas
`@PBI_QuantidadeMeses`, logo no início de cada consulta.

### Período fixo

Membros, contas técnicas e universo bruto usam os **mesmos períodos** das
referências, declarados no início de cada arquivo:

| Período | De | Até (exclusivo) |
|---|---|---|
| FEV | 01/02/2026 | 01/03/2026 |
| MAR | 09/03/2026 | 01/04/2026 |
| JUN | 01/06/2026 | 01/07/2026 |

Esses períodos estão amarrados a uma lista de analistas transcrita dos
relatórios do fornecedor para cada um deles. Um período automático não teria
lista e mudaria o resultado.

---

## 3. Saída

O Power BI lê apenas o **primeiro** resultado de uma consulta. Por isso:

- as consultas cuja referência devolve **um** resultado entregam esse resultado
  sem alteração, com as mesmas colunas, na mesma ordem;
- as consultas cuja referência devolve **vários** resultados entregam todos eles
  **empilhados** num único resultado, com a coluna `TipoResultado` dizendo de
  qual deles cada linha veio.

| Consulta | Valores de `TipoResultado`, na ordem da referência |
|---|---|
| satisfação | `JANELA_1_RESUMO`, `JANELA_2_DETALHE`, `CONFERENCIA` |
| validação | `SANIDADE`, `CONSISTENCIA`, `REGRESSOES`, `RESSALVAS` |
| membros | `RESUMO_PERIODO`, `POR_ANALISTA`, `DETALHE` |
| contas técnicas | `RESUMO_PERIODO`, `ORIGEM_DO_TOTAL`, `DETALHE` |
| universo bruto | `RESUMO`, `POR_CONTA_TECNICA`, `DETALHE` |

Nos resultados empilhados:

- cada linha traz preenchidas só as colunas do seu `TipoResultado`; as demais
  vêm vazias;
- colunas com o mesmo nome em mais de um resultado são a mesma coluna;
- as linhas saem na ordem da referência;
- colunas de texto saem como texto Unicode, com os mesmos valores.

No Power Query, basta filtrar `TipoResultado` para separar cada resultado.

A satisfação traz a conferência (`@MostrarConferencia = 1`) e usa a pergunta de
satisfação geral com a execução dos serviços (`@SequenciaPerguntaAvaliada = 40`),
como a referência. A de Encerrados não traz o resultado de diagnóstico
(`@MostrarDiagnostico = 0`), também como a referência.

---

## 4. Grupo alvo de Encerrados

Encerrados identifica o COI por **um** grupo alvo, escolhido em
`@COI_GrupoAlvo`: `@COI_Novo` (fila `COI`) ou `@COI_Antigo` (fila antiga, hoje
`Contrato 7/2023 - COI`). Os dois são declarados em cada consulta que os usa.

| Consulta do Power BI | Grupo alvo |
|---|---|
| Encerrados | `@COI_Novo` — igual à referência |
| Satisfação | `@COI_Novo` — igual à referência |
| Registrados × Encerrados por dia | `@COI_Novo` por padrão |

No **diário**, a referência vem com `@COI_Antigo`, preparada para conferência do
relatório de fevereiro de 2026. Ela própria indica `@COI_Novo` para produção, e
o período automático é sempre de produção; por isso a versão do Power BI usa
`@COI_Novo`. Para consultar o grupo anterior, troque a atribuição:

```sql
DECLARE @COI_GrupoAlvo varbinary(16) = @COI_Novo;     -- padrão do Power BI
DECLARE @COI_GrupoAlvo varbinary(16) = @COI_Antigo;   -- grupo anterior
```

Só a série `Encerrados` muda com essa troca; `Registrados` não usa o grupo alvo.
O grupo antigo não tem encerramentos depois de março de 2026: com ele, a série de
Encerrados fica vazia a partir de abril de 2026.

---

## 5. Colunas de diagnóstico do detalhe

O detalhe traz três colunas sobre grupos, com finalidades diferentes:

| Coluna | O que representa |
|---|---|
| `GrupoInit` | O valor informado em `%GROUP=` no evento de criação do chamado, normalizado. É informação auxiliar e pode não coincidir com o grupo em que o chamado nasceu |
| `PrimeiraOrigemGrupo` | O grupo de origem da primeira transferência de grupo legível do histórico. Quando há transferência, é a principal evidência de onde o chamado estava antes do primeiro movimento |
| `PrimeiroDestinoGrupo` | O grupo de destino dessa mesma primeira transferência. É a fila seguinte ao primeiro movimento, e não precisa ser o COI |

`GrupoInit` diferente de `PrimeiraOrigemGrupo` **não é erro**: o programa de
criação informou um valor e o chamado nasceu em outro grupo.
`InitConsistenteComReconstrucao` mostra essa comparação. As três colunas são de
diagnóstico; a entrada no indicador é decidida pela cadeia de transferências e
pelas demais regras de Registrados.

Exemplo: no SDM 1658863, `GrupoInit` é `VIRTUAL TI.ELABORAR/MANTER DOCUMENTAÇÃO`
— o nome de uma categoria, informado na criação —, `PrimeiraOrigemGrupo` é `COI`
e `PrimeiroDestinoGrupo` é `FORNECEDORES - VIRTUAL`. O chamado nasceu no COI e
entra no indicador como `ABERTO_NO_COI_CADEIA`, datado na abertura.

A descrição completa dessas colunas está na documentação de cálculo.

---

## 6. Montagem dos gráficos

| Gráfico | Consulta | Colunas |
|---|---|---|
| Registrados por mês | mensal | `MesAno` no eixo; `Incidentes` e `Solicitacoes` nas séries |
| Registrados × Encerrados por dia | diário | `Dia` no eixo; `Registrados` e `Encerrados` nas séries |
| Registrados por hora | por hora | `HoraLabel` no eixo, filtrado por `MesAno` |

As três usam o mesmo período, então o total de Registrados coincide entre elas.
As demais consultas são de auditoria e conciliação, e podem alimentar tabelas de
conferência.

---

## 7. Manutenção no Power Query

### Onde fica o SQL

**Página Inicial › Transformar dados** › selecione a consulta › em **Etapas
aplicadas**, clique na engrenagem da etapa **Fonte** › **Opções avançadas** ›
campo **Instrução SQL**. Depois de editar: **OK** › **Fechar e aplicar**, e
aprove a consulta nativa quando o Power BI pedir.

### Conexão

| Item | Valor |
|---|---|
| Conector | SQL Server |
| Banco de dados | `mdb` |
| Modo | Importação |
| Instrução SQL | o arquivo inteiro, sem selecionar trecho |
| Adicionar colunas de relação | desmarcado |

Cada consulta é somente leitura e roda num único lote. Cada atualização executa
a consulta inteira de novo e substitui os dados importados.

### Tempo de atualização

As consultas de Registrados leem o histórico de eventos de todos os chamados do
período e levam alguns minutos cada. Membros, contas técnicas e universo bruto
são as mais lentas, por causa da comparação de nomes da lista de analistas.

---

## 8. Conferência depois de atualizar

1. **Registrados fecham entre os gráficos.** A soma de `Total` do mensal, a soma
   de `Registrados` do diário e a soma de `QtdRegistrados` do por hora são
   iguais.
2. **Tipos fecham.** Em cada mês, `Incidentes` + `Solicitacoes` = `Total`.
3. **Calendário completo.** Seis linhas no mensal, uma linha por dia no diário e
   24 linhas por mês no por hora.
4. **Sem duplicidade.** No detalhe, número de linhas = número de SDMs
   distintos.
5. **Validação.** Na linha `SANIDADE`, as 16 asserções em `SIM`; na linha
   `CONSISTENCIA`, `Consistente` = `SIM`.
6. **Satisfação.** Na linha `CONFERENCIA`, `SomaFechaComEncerrados` = `SIM`.

---

## 9. Limitações

- **Registrados e Encerrados não são o mesmo universo.** Registrado é a primeira
  entrada no COI; Encerrado é o fechamento no grupo alvo. `Registrados` menos
  `Encerrados` não é o estoque em aberto do COI.
- **Conciliação só nos períodos com lista de analistas.** Membros, contas
  técnicas e universo bruto não acompanham o período automático.
- **Meses fechados podem mudar.** As consultas leem o estado atual da base; uma
  correção posterior num chamado muda o resultado de uma nova atualização.
- **Satisfação** depende do envio de pesquisa, que não está habilitado para as
  filas do COI: na maioria dos períodos, `Sem satisfação` é igual ao total.

---

## 10. Alertas de manutenção

- **A regra vive nas consultas de referência.** As consultas do Power BI são o
  texto delas, com as adaptações deste documento marcadas no próprio SQL com
  `[POWER BI]`. Uma mudança de regra é feita na referência e replicada na versão
  do Power BI.
- **Bloco canônico de Registrados.** O trecho entre `INICIO` e `FIM REGRA
  CANONICA DE REGISTRADOS COI` é idêntico, byte a byte, nas sete consultas de
  Registrados de referência e nas sete do Power BI. A igualdade é conferida pelo
  SHA256 do trecho.
- **Bloco das contas técnicas.** O trecho `REGRA COMPARTILHADA TECNICOS COI` é
  idêntico nas duas consultas de contas técnicas e nas duas versões do Power BI.
- **Valores que não são parâmetros.** `@TransIniBR`, `@TransFimBR`, os UUIDs do
  COI, a lista de nomes do COI e a lista de filas do Task Scheduler descrevem
  fatos; não são ajustes de período.
- **Colunas empilhadas.** Os nomes e a ordem das colunas de cada resultado são os
  da referência. Uma coluna nova na referência precisa entrar também na tabela de
  saída da versão do Power BI.
