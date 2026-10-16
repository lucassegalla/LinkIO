# Latch

O Latch é um projeto de automação que integra um aplicativo mobile desenvolvido em Flutter a um dispositivo ESP8266. O sistema permite controlar um LED pela rede Wi-Fi local, ligar ou desligar a iluminação e ajustar sua intensidade.

O repositório reúne o aplicativo mobile e o firmware que executa no microcontrolador.

## Sumário

- [Objetivo](#objetivo)
- [Tecnologias utilizadas](#tecnologias-utilizadas)
- [Arquitetura](#arquitetura)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Funcionalidades](#funcionalidades)
- [Hardware](#hardware)
- [Como executar](#como-executar)
- [Comunicação com o ESP8266](#comunicação-com-o-esp8266)
- [Endpoints](#endpoints)
- [Solução de problemas](#solução-de-problemas)
- [Roadmap](#roadmap)
- [Autor](#autor)

## Objetivo

O projeto foi desenvolvido para explorar a integração entre um aplicativo mobile e um dispositivo físico conectado à rede local. O aplicativo envia requisições HTTP ao ESP8266, que interpreta os comandos e controla o LED conectado à placa.

A implementação atual utiliza um LED de baixa tensão como demonstração. O controle de brilho é feito por PWM, permitindo variar a intensidade luminosa sem alterar o circuito.

## Tecnologias utilizadas

### Aplicativo mobile

- **Dart** - Linguagem de programação do aplicativo
- **Flutter** - Framework para desenvolvimento da interface mobile
- **HTTP** - Comunicação com a API local do ESP8266
- **multicast_dns** - Biblioteca utilizada na tentativa de descoberta de dispositivos por mDNS

### Firmware e hardware

- **C++ / Arduino IDE** - Desenvolvimento e gravação do firmware
- **ESP8266 ESP-12E / NodeMCU** - Microcontrolador com conectividade Wi-Fi
- **ESP8266WebServer** - Servidor HTTP executado na placa
- **PWM** - Controle da intensidade luminosa do LED

## Arquitetura

O aplicativo e o microcontrolador se comunicam por HTTP através da rede Wi-Fi local.

```text
Aplicativo Flutter
       |
       | Requisições HTTP
       v
Servidor HTTP no ESP8266
       |
       | GPIO / PWM
       v
      LED
```

### Aplicativo Flutter

Responsável pela interface de controle. Permite adicionar um dispositivo pelo endereço IP, consultar seu estado, ligar ou desligar o LED, ajustar o brilho e atualizar as informações exibidas.

### Firmware ESP8266

Conecta-se à rede Wi-Fi configurada no código e inicia um servidor HTTP na porta `80`. O firmware recebe comandos do aplicativo e controla o LED conectado ao pino `D1` (GPIO5).

### Comunicação

As requisições e respostas utilizam JSON. O aplicativo e o ESP8266 devem estar conectados à mesma rede local para que o celular consiga acessar o endereço IP da placa.

## Estrutura do projeto

```text
latch/
├── README.md
├── firmware/
│   └── latch_esp8266/
│       └── latch_esp8266.ino
└── latch_mobile/
    ├── android/
    ├── lib/
    │   └── main.dart
    ├── test/
    │   └── widget_test.dart
    ├── firmware/
    │   └── latch_esp32.ino
    ├── pubspec.yaml
    └── pubspec.lock
```

O arquivo `firmware/latch_esp8266/latch_esp8266.ino` contém o firmware usado no protótipo ESP8266. O arquivo `latch_mobile/firmware/latch_esp32.ino` é um exemplo separado de firmware para ESP32 e não corresponde à placa ESP8266 descrita nas instruções principais.

## Funcionalidades

### Aplicativo mobile

- Adicionar um dispositivo pelo endereço IP
- Consultar o estado do LED e o brilho atual
- Ligar e desligar o LED
- Ajustar a intensidade luminosa com um controle deslizante
- Atualizar o estado de um dispositivo cadastrado
- Exibir o endereço e a condição de conexão do dispositivo
- Iniciar uma busca por dispositivos compatíveis via mDNS

A busca automática depende de os dispositivos anunciarem o serviço HTTP via mDNS. O firmware ESP8266 descrito neste README não anuncia esse serviço; por isso, a conexão manual pelo endereço IP é o método recomendado para o protótipo atual.

### Firmware

- Conectar-se a uma rede Wi-Fi
- Iniciar um servidor HTTP na porta `80`
- Retornar o estado do LED em JSON
- Receber comandos para ligar e desligar
- Ajustar o brilho entre `0` e `100`
- Controlar a saída PWM do LED

## Hardware

O protótipo utiliza uma placa NodeMCU ESP8266 ESP-12E, um LED e um resistor limitador de corrente.

Ligação utilizada:

```text
D1 (GPIO5) ── Resistor (220–330 Ω) ── Perna longa do LED
GND        ────────────────────────── Perna curta do LED
```

Use um resistor em série com o LED para limitar a corrente. Não conecte uma lâmpada ligada à rede elétrica diretamente aos pinos do ESP8266.

## Como executar

### 1. Configurar o firmware

Abra `firmware/latch_esp8266/latch_esp8266.ino` na Arduino IDE. Certifique-se de que o suporte à placa ESP8266 esteja instalado, selecione uma placa NodeMCU ESP8266 compatível e escolha a porta serial correspondente.

No início do arquivo, configure o nome e a senha da rede Wi-Fi:

```cpp
const char* ssid = "NOME_DA_REDE";
const char* password = "SENHA_DA_REDE";
```

Substitua `NOME_DA_REDE` pelo SSID da rede e `SENHA_DA_REDE` pela senha correspondente. Mantenha valores de exemplo no arquivo enviado ao GitHub e coloque as credenciais reais apenas na sua cópia local. Não publique sua senha de Wi-Fi no repositório.

Compile e grave o firmware na placa. Abra o Monitor Serial com velocidade de `115200` baud. Após conectar à rede, o firmware imprime o endereço IP atribuído ao ESP8266.

### 2. Executar o aplicativo Flutter

Instale o Flutter e configure as ferramentas de desenvolvimento para Android. No terminal, entre na pasta do aplicativo:

```powershell
cd latch_mobile
flutter pub get
flutter devices
```

Conecte o celular Android por USB, ative a depuração USB e autorize o computador no celular. Depois execute o aplicativo, usando o identificador mostrado por `flutter devices`:

```powershell
flutter run -d ID_DO_DISPOSITIVO
```

Para gerar um APK de depuração:

```powershell
flutter build apk --debug
```

### 3. Conectar ao ESP8266

Confirme que o celular e a placa estão conectados à mesma rede Wi-Fi. No aplicativo, pressione **Adicionar**, informe o endereço IP exibido no Monitor Serial e conecte-se.

O endereço IP pode mudar quando a placa se reconectar à rede. Se isso acontecer, consulte novamente o Monitor Serial e atualize o endereço usado no aplicativo.

## Comunicação com o ESP8266

A API local usa a porta `80`. Nos exemplos abaixo, `192.168.100.170` é um endereço ilustrativo; utilize o IP atual da placa.

### Consultar o estado

```http
GET /api/status
```

Exemplo de resposta:

```json
{
  "light": true,
  "brightness": 70
}
```

- `light`: indica se o LED está ligado.
- `brightness`: intensidade configurada, entre `0` e `100`.

### Ligar ou desligar o LED

```http
POST /api/light
Content-Type: application/json
```

Corpo para ligar:

```json
{
  "on": true
}
```

Corpo para desligar:

```json
{
  "on": false
}
```

A resposta contém o estado atualizado do LED e o brilho configurado.

### Ajustar o brilho

```http
POST /api/brightness
Content-Type: application/json
```

Exemplo de corpo:

```json
{
  "brightness": 50
}
```

O campo `brightness` deve ser um número inteiro entre `0` e `100`. Definir o brilho como `0` desliga o LED; valores maiores que zero ligam o LED e ajustam a intensidade.

## Endpoints

| Método | Endpoint | Descrição |
| :--- | :--- | :--- |
| `GET` | `/` | Verifica se o servidor do Latch está respondendo |
| `GET` | `/api/status` | Consulta o estado do LED e o brilho |
| `POST` | `/api/light` | Liga ou desliga o LED |
| `POST` | `/api/brightness` | Define a intensidade luminosa entre 0 e 100 |

## Solução de problemas

- **O aplicativo não conecta:** confirme que o celular e o ESP8266 estão na mesma rede Wi-Fi e que o endereço IP está correto.
- **O IP não aparece:** confira as credenciais configuradas no firmware e observe as mensagens no Monitor Serial a `115200` baud.
- **O dispositivo fica offline:** verifique a alimentação da placa, a conexão Wi-Fi e se o servidor HTTP foi iniciado.
- **A busca automática não encontra o ESP8266:** use a conexão manual por IP. A descoberta mDNS requer que o dispositivo anuncie o serviço HTTP, recurso que não está configurado no firmware ESP8266 atual.
- **O LED não altera o brilho:** confira a ligação do LED ao pino `D1` (GPIO5), o resistor em série e se o firmware correto foi gravado na placa.

## Roadmap

- [x] Comunicação HTTP entre o aplicativo e o ESP8266
- [x] Controle para ligar e desligar o LED
- [x] Ajuste de brilho por PWM
- [x] Consulta do estado do dispositivo
- [x] Cadastro manual por endereço IP
- [ ] Implementar anúncio mDNS no firmware ESP8266 para permitir descoberta automática
- [ ] Melhorar o feedback visual de erros e de conexão
- [ ] Evoluir o suporte a múltiplos dispositivos

## Autor

Desenvolvido por **Lucas Wallace Segalla**.

- GitHub: https://github.com/lucassegalla
