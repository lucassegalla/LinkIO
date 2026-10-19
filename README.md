# LinkIO

Aplicativo mobile desenvolvido com Flutter para descobrir e controlar dispositivos ESP8266 pela rede Wi-Fi local. O projeto combina uma interface para celular, um firmware Arduino e uma API HTTP local para comandar um motor de passo e uma saída de iluminação RGB.

O LinkIO está em desenvolvimento como protótipo de automação e comunicação entre software e hardware. Não utiliza backend, banco de dados ou serviços em nuvem: o aplicativo conversa diretamente com o ESP8266.

## Sumário

- [Objetivo](#objetivo)
- [Demonstração](#demonstração)
- [Tecnologias utilizadas](#tecnologias-utilizadas)
- [Arquitetura](#arquitetura)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Funcionalidades](#funcionalidades)
- [Hardware e conexões](#hardware-e-conexões)
- [Como executar](#como-executar)
- [API HTTP](#api-http)
- [Limitações e segurança](#limitações-e-segurança)
- [Solução de problemas](#solução-de-problemas)
- [Roadmap](#roadmap)
- [Autor](#autor)

## Objetivo

O LinkIO começou como um protótipo de controle local por Wi-Fi e evoluiu para um sistema que integra um aplicativo mobile a um microcontrolador. O objetivo é praticar desenvolvimento Flutter, comunicação HTTP, descoberta de dispositivos na rede, programação de microcontroladores e acionamento de componentes físicos.

## Demonstração

O fluxo de uso previsto é:

1. Conectar o celular e o ESP8266 à mesma rede Wi-Fi.
2. Iniciar o firmware e consultar o endereço IP exibido no Monitor Serial.
3. Abrir o LinkIO e procurar dispositivos na rede ou adicionar o endereço IP manualmente.
4. Expandir o cartão do dispositivo para acessar os controles.
5. Comandar o motor de passo, selecionar uma cor, ajustar os canais RGB e alterar o brilho.
6. Atualizar o estado para verificar se o dispositivo continua respondendo.

As capturas de tela da interface ainda precisam ser organizadas e referenciadas no repositório. A documentação pode ser complementada com imagens da aplicação quando estiverem disponíveis em uma pasta como `docs/images/`.

## Tecnologias utilizadas

### Aplicativo mobile

- **Dart:** linguagem utilizada no aplicativo.
- **Flutter:** desenvolvimento da interface e execução multiplataforma.
- **Material 3:** componentes e tema visual.
- **`http`:** requisições HTTP ao ESP8266.
- **`multicast_dns`:** descoberta de serviços por mDNS na rede local.
- **`shared_preferences`:** armazenamento local dos nomes personalizados dos dispositivos.

### Firmware e comunicação

- **Arduino IDE:** edição e gravação do firmware.
- **ESP8266 Arduino Core:** ambiente de desenvolvimento do microcontrolador.
- **`ESP8266WiFi`:** conexão à rede Wi-Fi.
- **`ESP8266WebServer`:** servidor HTTP local.
- **`ESP8266mDNS`:** anúncio do serviço para descoberta na rede.
- **`ArduinoJson`:** biblioteca utilizada no firmware para trabalhar com dados JSON.
- **HTTP e JSON:** protocolo utilizado entre o aplicativo e o microcontrolador.
- **PWM e GPIO:** controle das saídas físicas.

### Hardware

- Placa baseada em ESP8266, como NodeMCU ESP-12E.
- Motor de passo de quatro fases compatível com o driver utilizado.
- Driver para motor de passo, como o ULN2003 quando utilizado com um motor compatível.
- LED ou módulo RGB de baixa tensão com resistores apropriados.
- Fonte de alimentação adequada aos componentes conectados.

## Arquitetura

O LinkIO utiliza comunicação direta dentro da rede local. Não existe um backend intermediário.

```text
┌──────────────────────────────┐
│       Aplicativo Flutter     │
│                              │
│ Descoberta mDNS              │
│ Conexão manual por IP        │
│ Controles de motor e RGB     │
└──────────────┬───────────────┘
               │
               │ HTTP + JSON
               │ Rede Wi-Fi local
               ▼
┌──────────────────────────────┐
│           ESP8266            │
│                              │
│ Servidor HTTP                │
│ API de controle              │
│ Estado atual do dispositivo  │
└──────────────┬───────────────┘
               │
         ┌─────┴─────┐
         ▼           ▼
┌──────────────┐ ┌──────────────┐
│ Driver e     │ │ Saídas RGB   │
│ motor de     │ │ controladas  │
│ passo        │ │ por PWM      │
└──────────────┘ └──────────────┘
```

### Aplicativo Flutter

A interface localiza dispositivos compatíveis, mantém a lista de conexões em memória durante a execução e envia comandos à API. Os nomes personalizados dos dispositivos são armazenados localmente com `shared_preferences`.

### Firmware ESP8266

O microcontrolador conecta-se à rede Wi-Fi, inicia um servidor HTTP na porta `80` e processa requisições para consultar o estado ou alterar o motor e a iluminação. Os comandos são convertidos em sinais GPIO e PWM.

### Descoberta e conexão

O aplicativo consulta serviços HTTP anunciados por mDNS. Quando a descoberta não funciona na rede, é possível informar o IP e, quando necessário, a porta do dispositivo manualmente.

## Estrutura do projeto

A estrutura principal documentada é:

```text
.
├── firmware/
│   └── latch_esp8266/
│       └── latch_esp8266.ino    # Firmware do ESP8266
├── latch_mobile/
│   ├── android/                 # Configuração Android
│   ├── lib/
│   │   └── main.dart            # Interface e comunicação HTTP
│   ├── pubspec.yaml             # Dependências do Flutter
│   └── pubspec.lock             # Versões resolvidas das dependências
└── README.md                    # Documentação do projeto
```

Arquivos auxiliares gerados pelo Flutter, como `build/`, `.dart_tool/` e caches locais, não fazem parte da estrutura principal a ser versionada.

## Funcionalidades

### Descoberta e gerenciamento de dispositivos

- Busca de dispositivos HTTP na rede local por mDNS.
- Adição manual de um dispositivo por endereço IP e porta opcional.
- Consulta do endpoint de status para validar a conexão.
- Exibição de endereço, porta e estado online/offline.
- Atualização manual do estado do dispositivo.
- Renomeação de dispositivos com persistência local do nome personalizado.
- Cartões individuais que podem ser expandidos ou recolhidos.
- Opções para renomear ou desconectar um dispositivo.
- Ao desconectar, o aplicativo tenta enviar comandos de parada aos motores dos dispositivos conectados. Esse procedimento é uma tentativa de melhor esforço e não substitui uma parada de emergência física.

### Motor de passo

- Ligar e desligar o motor.
- Selecionar o sentido horário ou anti-horário.
- Exibir o estado informado pelo firmware.
- Gerar a sequência de acionamento das bobinas no ESP8266.

O sentido é enviado como `1` para horário e `-1` para anti-horário. A velocidade de acionamento é definida no firmware e não é configurável pela API atual.

### Iluminação RGB

- Ligar e desligar a saída de iluminação.
- Selecionar cores predefinidas: vermelho, verde, azul, branco, amarelo, ciano, magenta e desligado.
- Ajustar manualmente os canais vermelho, verde e azul.
- Ajustar o brilho em uma faixa de `0` a `100`.
- Consultar o estado e os valores atuais retornados pelo firmware.

Os controles operam as saídas RGB conectadas ao ESP8266. Eles não significam, por si só, que uma lâmpada inteligente comercial esteja integrada ao projeto.

### Estado e falhas de comunicação

- Leitura do estado por `GET /api/status`.
- Atualização visual dos valores recebidos.
- Indicação de dispositivos que não respondem.
- Mensagens de erro quando uma requisição falha ou retorna um status HTTP diferente de `200`.

## Hardware e conexões

As associações de pinos descritas no firmware atual são:

| Componente | Sinal | Pino ESP8266 |
| :-- | :-- | :-- |
| Driver do motor | IN1 | `D5` |
| Driver do motor | IN2 | `D6` |
| Driver do motor | IN3 | `D7` |
| Driver do motor | IN4 | `D2` |
| RGB | Vermelho | `D1` |
| RGB | Verde | `D3` |
| RGB | Azul | `D4` |

**Cuidados com o hardware:**

- Não alimente o motor diretamente pelos GPIOs do ESP8266. Utilize o driver apropriado e uma alimentação compatível com o motor.
- Garanta uma referência de terra comum quando a fonte externa e a placa precisarem compartilhar sinais de controle.
- Utilize resistores limitadores de corrente apropriados para LEDs RGB discretos.
- Confira a pinagem real da placa e do módulo antes de energizar o circuito.
- **Nunca conecte uma lâmpada ligada à rede elétrica diretamente ao ESP8266.** Para cargas de potência, utilize equipamento apropriado, isolação elétrica e instalação compatível com as normas de segurança.

## Como executar

São necessários dois ambientes: um para gravar o firmware no ESP8266 e outro para executar o aplicativo Flutter.

### 1. Preparar o firmware

1. Instale a Arduino IDE.
2. Instale o pacote de placas ESP8266 pelo gerenciador de placas da IDE.
3. Instale a biblioteca `ArduinoJson`, caso ela não esteja disponível no ambiente.
4. Abra `firmware/latch_esp8266/latch_esp8266.ino`.
5. Configure as constantes `ssid` e `password` com os dados da sua rede Wi-Fi.
6. Selecione a placa ESP8266 apropriada e a porta serial correta.
7. Compile e grave o firmware.
8. Abra o Monitor Serial a `115200` baud e anote o endereço IP apresentado.

**Segurança:** não publique a senha real da rede Wi-Fi no repositório. Antes de enviar alterações ao GitHub, substitua credenciais reais por valores fictícios ou mova-as para um arquivo de configuração local que não seja versionado.

### 2. Preparar o aplicativo

Instale o Flutter SDK e configure o Android SDK. Em seguida, abra um terminal na pasta do aplicativo:

```bash
cd latch_mobile
flutter pub get
```

Verifique os dispositivos disponíveis:

```bash
flutter devices
```

Execute o aplicativo em um dispositivo selecionado:

```bash
flutter run -d <ID_DO_DISPOSITIVO>
```

Para usar o dispositivo padrão detectado pelo Flutter:

```bash
flutter run
```

Para verificar estaticamente o projeto:

```bash
flutter analyze
```

Para gerar um APK de depuração:

```bash
flutter build apk --debug
```

O APK de depuração é gerado em `build/app/outputs/flutter-apk/app-debug.apk`, dentro da pasta `latch_mobile`.

### 3. Conectar o aplicativo ao ESP8266

1. Conecte o celular e a placa à mesma rede Wi-Fi.
2. Inicie o firmware e localize o IP no Monitor Serial.
3. Abra o LinkIO e execute a busca de dispositivos.
4. Se o dispositivo não aparecer, use a opção de adicionar manualmente e informe o IP.
5. Expanda o cartão do dispositivo para acessar os controles.
6. Utilize a atualização de estado para confirmar a comunicação.

O IP do ESP8266 pode mudar conforme a configuração do roteador. Se isso acontecer, consulte novamente o Monitor Serial e atualize o endereço utilizado pelo aplicativo.

## API HTTP

O firmware expõe uma API HTTP na porta `80`. As requisições são locais e utilizam JSON nos endpoints de comando.

### Endpoints

| Método | Endpoint | Descrição |
| :-- | :-- | :-- |
| `GET` | `/` | Verifica se o servidor HTTP está respondendo. |
| `GET` | `/api/status` | Retorna o estado atual do dispositivo. |
| `POST` | `/api/motor` | Altera o estado e o sentido do motor. |
| `POST` | `/api/rgb` | Seleciona uma cor predefinida ou define valores RGB. |
| `POST` | `/api/brightness` | Define o brilho entre `0` e `100`. |
| `POST` | `/api/light` | Liga ou desliga a iluminação. |

### Consultar o estado

Requisição:

```http
GET /api/status
```

Exemplo de resposta:

```json
{
  "name": "LinkIO",
  "light": false,
  "brightness": 100,
  "red": 0,
  "green": 0,
  "blue": 0,
  "color": "off",
  "motorRunning": false,
  "motorDirection": 1
}
```

### Controlar o motor

Para iniciar o motor no sentido horário:

```http
POST /api/motor
Content-Type: application/json

{
  "running": true,
  "direction": 1
}
```

Para selecionar o sentido anti-horário e manter o motor ligado:

```json
{
  "running": true,
  "direction": -1
}
```

Para solicitar a parada:

```json
{
  "running": false,
  "direction": 1
}
```

O valor `direction` deve ser `1` para horário ou `-1` para anti-horário. O firmware atual utiliza um intervalo fixo entre os passos.

### Selecionar uma cor predefinida

```http
POST /api/rgb
Content-Type: application/json

{
  "color": "cyan"
}
```

As cores aceitas são `red`, `green`, `blue`, `white`, `yellow`, `cyan`, `magenta` e `off`.

### Definir valores RGB manualmente

```http
POST /api/rgb
Content-Type: application/json

{
  "red": 255,
  "green": 0,
  "blue": 100
}
```

Cada canal é limitado à faixa de `0` a `255`. O firmware define o modo da iluminação como personalizado quando recebe valores RGB.

### Ajustar o brilho

```http
POST /api/brightness
Content-Type: application/json

{
  "brightness": 50
}
```

O brilho aceita inteiros de `0` a `100`. No firmware atual, definir o brilho como `0` também desliga a saída de iluminação.

### Ligar ou desligar a iluminação

Para ligar:

```http
POST /api/light
Content-Type: application/json

{
  "on": true
}
```

Para desligar:

```json
{
  "on": false
}
```

Ao ligar, se os canais RGB estiverem todos zerados, o firmware seleciona branco para produzir uma saída visível.

### Respostas de erro

O firmware utiliza `400 Bad Request` para requisições sem os dados necessários ou com valores inválidos, e `404 Not Found` para rotas não reconhecidas. Em caso de sucesso, os endpoints de comando retornam o estado atualizado em JSON.

## Limitações e segurança

- **Rede local:** o aplicativo foi projetado para se comunicar diretamente com dispositivos acessíveis pela rede Wi-Fi local. Não existe controle remoto pela internet nem serviço de nuvem.
- **Sem autenticação e HTTPS:** a API utiliza HTTP sem autenticação. Qualquer dispositivo com acesso à rede e ao endereço do ESP8266 pode tentar enviar comandos. Utilize uma rede confiável e não exponha a porta do microcontrolador à internet.
- **Credenciais Wi-Fi:** o firmware utiliza constantes de configuração para o SSID e a senha. Não versione valores reais.
- **Descoberta mDNS:** no estado atual, o firmware anuncia o serviço com o nome `linkio-esp8266`, enquanto o aplicativo filtra instâncias cujo nome começa com `latch`. Essa diferença pode impedir que a busca automática encontre a placa. Até os dois lados serem alinhados, a conexão manual por IP é a alternativa mais direta.
- **Nome exibido no Monitor Serial:** a mensagem de diagnóstico do firmware deve ser mantida consistente com o hostname realmente registrado via mDNS.
- **Estado dos dispositivos:** o aplicativo consulta o estado do firmware. Os nomes personalizados são salvos localmente, mas a aplicação não utiliza um servidor central para sincronizar configurações entre celulares.
- **Lâmpada comercial:** a versão atual controla as saídas do ESP8266. O controle de uma lâmpada Wi-Fi comercial requer uma integração específica e não deve ser presumido.
- **Segurança física:** comandos HTTP não são um mecanismo de parada de emergência. Equipamentos que apresentem risco devem possuir meios físicos independentes de desligamento.

## Solução de problemas

| Problema | Possíveis verificações |
| :-- | :-- |
| O dispositivo não aparece na busca | Confirme a mesma rede Wi-Fi, verifique o IP no Monitor Serial e confira o nome mDNS anunciado pelo firmware em relação ao filtro do aplicativo. |
| A conexão manual falha | Revise o IP e a porta, confirme que o firmware iniciou e teste `http://IP_DO_ESP8266/api/status` em um navegador na mesma rede. |
| O dispositivo fica offline | Confirme a alimentação da placa, o Wi-Fi e se o roteador atribuiu um novo IP. |
| O aplicativo não compila | Execute `flutter pub get` e depois `flutter analyze` para verificar dependências e erros reportados. |
| O motor vibra, mas não gira corretamente | Confira a ordem das bobinas, a ligação ao driver, a alimentação e a compatibilidade entre o motor e o padrão de acionamento. |
| A iluminação RGB apresenta cores incorretas | Verifique a identificação dos canais, a ligação dos pinos e os resistores utilizados. |

## Roadmap

### Concluído

- [x] Aplicativo Flutter para controle local de dispositivos.
- [x] Comunicação HTTP com payloads JSON.
- [x] Consulta do estado do ESP8266.
- [x] Adição manual de dispositivos por IP e porta.
- [x] Implementação de busca automática por mDNS.
- [x] Controle do motor de passo e seleção de sentido.
- [x] Presets de cores RGB e controle manual dos canais.
- [x] Ajuste de brilho.
- [x] Indicação de estado online/offline e atualização manual.
- [x] Renomeação local dos dispositivos com persistência.
- [x] Cartões expansíveis e opção de desconexão.
- [x] Verificação estática do aplicativo com `flutter analyze`.
- [x] Execução e compilação de depuração em Android.

### Próximos passos

- [ ] Alinhar o nome mDNS anunciado pelo firmware com o filtro usado pelo aplicativo.
- [ ] Externalizar as credenciais Wi-Fi e garantir que não sejam enviadas ao Git.
- [ ] Organizar capturas de tela da aplicação em `docs/images/`.
- [ ] Expandir os testes físicos do motor e da iluminação em diferentes condições de alimentação.
- [ ] Avaliar uma integração separada caso o objetivo seja controlar uma lâmpada inteligente comercial.

## Autor

Desenvolvido por **Lucas Wallace Segalla**.

- GitHub: https://github.com/lucassegalla
- LinkedIn: https://linkedin.com/in/lucassegalla