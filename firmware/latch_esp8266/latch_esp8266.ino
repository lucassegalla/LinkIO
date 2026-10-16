#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

const char* ssid = "NOME_WIFI";
const char* password = "SENHA_WIFI";

ESP8266WebServer servidor(80);

// Na NodeMCU ESP8266 ESP-12E, D1 corresponde ao GPIO5.
const uint8_t PINO_LED = D1;
const int BRILHO_MAXIMO = 1023;

bool luzLigada = false;
int brilhoPercentual = 70;

void aplicarEstadoLed() {
  const int brilhoPwm = luzLigada
      ? map(brilhoPercentual, 0, 100, 0, BRILHO_MAXIMO)
      : 0;

  analogWrite(PINO_LED, brilhoPwm);
}

void enviarEstado() {
  String resposta = "{\"light\":";
  resposta += luzLigada ? "true" : "false";
  resposta += ",\"brightness\":";
  resposta += String(brilhoPercentual);
  resposta += "}";

  servidor.send(200, "application/json", resposta);
}

void configurarRotas() {
  servidor.on("/", HTTP_GET, []() {
    servidor.send(200, "text/plain", "Latch ESP8266 online!");
  });

  servidor.on("/api/status", HTTP_GET, []() {
    enviarEstado();
  });

  // Mantém compatibilidade com o app atual: {"on":true} ou {"on":false}.
  servidor.on("/api/light", HTTP_POST, []() {
    if (!servidor.hasArg("plain")) {
      servidor.send(400, "application/json",
                    "{\"error\":\"Corpo da requisicao ausente\"}");
      return;
    }

    String corpo = servidor.arg("plain");
    corpo.replace(" ", "");
    corpo.replace("\n", "");
    corpo.replace("\r", "");
    corpo.replace("\t", "");

    if (corpo.indexOf("\"on\":true") >= 0) {
      luzLigada = true;
      // Ao ligar, restaura um brilho visível se o brilho estava em zero.
      if (brilhoPercentual == 0) brilhoPercentual = 70;
    } else if (corpo.indexOf("\"on\":false") >= 0) {
      luzLigada = false;
    } else {
      servidor.send(400, "application/json",
                    "{\"error\":\"Comando invalido\"}");
      return;
    }

    aplicarEstadoLed();
    enviarEstado();
  });

  // Recebe JSON no formato {"brightness":50}, entre 0 e 100.
  servidor.on("/api/brightness", HTTP_POST, []() {
    if (!servidor.hasArg("plain")) {
      servidor.send(400, "application/json",
                    "{\"error\":\"Corpo da requisicao ausente\"}");
      return;
    }

    String corpo = servidor.arg("plain");
    const int inicio = corpo.indexOf("\"brightness\"");
    const int doisPontos = corpo.indexOf(':', inicio);

    if (inicio < 0 || doisPontos < 0) {
      servidor.send(400, "application/json",
                    "{\"error\":\"Envie brightness como inteiro de 0 a 100\"}");
      return;
    }

    int fim = corpo.indexOf(',', doisPontos);
    if (fim < 0) fim = corpo.indexOf('}', doisPontos);
    if (fim < 0) {
      servidor.send(400, "application/json",
                    "{\"error\":\"JSON invalido\"}");
      return;
    }

    String valor = corpo.substring(doisPontos + 1, fim);
    valor.trim();
    const int novoBrilho = valor.toInt();

    // Rejeita valores não numéricos e valores fora do intervalo.
    if (valor.length() == 0 ||
        (valor != "0" && novoBrilho == 0) ||
        novoBrilho < 0 || novoBrilho > 100) {
      servidor.send(400, "application/json",
                    "{\"error\":\"O brilho deve estar entre 0 e 100\"}");
      return;
    }

    brilhoPercentual = novoBrilho;
    luzLigada = brilhoPercentual > 0;
    aplicarEstadoLed();
    enviarEstado();
  });

  servidor.onNotFound([]() {
    servidor.send(404, "application/json",
                  "{\"error\":\"Rota nao encontrada\"}");
  });
}

void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(PINO_LED, OUTPUT);
  analogWriteRange(BRILHO_MAXIMO);
  analogWriteFreq(1000);
  aplicarEstadoLed();

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  Serial.print("Conectando ao Wi-Fi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  configurarRotas();
  servidor.begin();

  Serial.println();
  Serial.println("Latch iniciado!");
  Serial.print("IP: ");
  Serial.println(WiFi.localIP());
  Serial.println("Servidor HTTP na porta 80");
}

void loop() {
  servidor.handleClient();
}
