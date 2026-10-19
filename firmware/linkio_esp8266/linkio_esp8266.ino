
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266mDNS.h>
#include <ArduinoJson.h>

// Configure sua rede Wi-Fi localmente.
const char* ssid = "nome-rede-wifi";
const char* password = "senha-wifi";

ESP8266WebServer servidor(80);

// Motor 28BYJ-48 + ULN2003
const uint8_t IN1 = D5;
const uint8_t IN2 = D6;
const uint8_t IN3 = D7;
const uint8_t IN4 = D2;

// LED RGB
const uint8_t LED_R = D1;
const uint8_t LED_G = D3;
const uint8_t LED_B = D4;

// Sequencia de meio passo do motor
const uint8_t sequencia[8][4] = {
  {1, 0, 0, 0},
  {1, 1, 0, 0},
  {0, 1, 0, 0},
  {0, 1, 1, 0},
  {0, 0, 1, 0},
  {0, 0, 1, 1},
  {0, 0, 0, 1},
  {1, 0, 0, 1}
};

// Estado do motor
bool motorLigado = false;
int direcaoMotor = 1;
int passoAtual = 0;

const unsigned long intervaloPasso = 3;
unsigned long ultimoPasso = 0;

// Estado da iluminacao
bool luzLigada = false;

int vermelho = 0;
int verde = 0;
int azul = 0;
int brilho = 100;

String corAtual = "off";

// --------------------------------------------------
// LED RGB
// --------------------------------------------------

void aplicarRGB() {
  if (!luzLigada) {
    analogWrite(LED_R, 0);
    analogWrite(LED_G, 0);
    analogWrite(LED_B, 0);
    return;
  }

  analogWrite(LED_R, vermelho * brilho / 100);
  analogWrite(LED_G, verde * brilho / 100);
  analogWrite(LED_B, azul * brilho / 100);
}

void selecionarCor(String cor) {
  cor.toLowerCase();

  if (cor == "red") {
    vermelho = 255;
    verde = 0;
    azul = 0;
  } else if (cor == "green") {
    vermelho = 0;
    verde = 255;
    azul = 0;
  } else if (cor == "blue") {
    vermelho = 0;
    verde = 0;
    azul = 255;
  } else if (cor == "white") {
    vermelho = 255;
    verde = 255;
    azul = 255;
  } else if (cor == "yellow") {
    vermelho = 255;
    verde = 255;
    azul = 0;
  } else if (cor == "cyan") {
    vermelho = 0;
    verde = 255;
    azul = 255;
  } else if (cor == "magenta") {
    vermelho = 255;
    verde = 0;
    azul = 255;
  } else if (cor == "off") {
    vermelho = 0;
    verde = 0;
    azul = 0;
    corAtual = "off";
    luzLigada = false;
    aplicarRGB();
    return;
  } else {
    return;
  }

  corAtual = cor;
  luzLigada = true;
  aplicarRGB();
}

// --------------------------------------------------
// Motor
// --------------------------------------------------

void liberarMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, LOW);
}

void atualizarMotor() {
  if (!motorLigado) {
    return;
  }

  const unsigned long agora = millis();

  if (agora - ultimoPasso >= intervaloPasso) {
    ultimoPasso = agora;

    if (direcaoMotor > 0) {
      passoAtual = (passoAtual + 1) % 8;
    } else {
      passoAtual = (passoAtual + 7) % 8;
    }

    digitalWrite(IN1, sequencia[passoAtual][0]);
    digitalWrite(IN2, sequencia[passoAtual][1]);
    digitalWrite(IN3, sequencia[passoAtual][2]);
    digitalWrite(IN4, sequencia[passoAtual][3]);
  }
}

// --------------------------------------------------
// Resposta de status
// --------------------------------------------------

void responderStatus() {
  StaticJsonDocument<384> doc;

  doc["name"] = "LinkIO";
  doc["light"] = luzLigada;
  doc["brightness"] = brilho;
  doc["red"] = vermelho;
  doc["green"] = verde;
  doc["blue"] = azul;
  doc["color"] = corAtual;
  doc["motorRunning"] = motorLigado;
  doc["motorDirection"] = direcaoMotor;

  String resposta;
  serializeJson(doc, resposta);

  servidor.send(200, "application/json", resposta);
}

void erroJSON(const char* mensagem) {
  StaticJsonDocument<128> doc;
  doc["error"] = mensagem;

  String resposta;
  serializeJson(doc, resposta);

  servidor.send(400, "application/json", resposta);
}

// --------------------------------------------------
// Rotas HTTP
// --------------------------------------------------

void configurarRotas() {
  servidor.on("/", HTTP_GET, []() {
    servidor.send(200, "text/plain", "LinkIO ESP8266 online");
  });

  servidor.on("/api/status", HTTP_GET, responderStatus);

  // Ligar/desligar motor e selecionar sentido
  servidor.on("/api/motor", HTTP_POST, []() {
    StaticJsonDocument<192> doc;

    if (deserializeJson(doc, servidor.arg("plain"))) {
      erroJSON("JSON invalido");
      return;
    }

    if (doc.containsKey("direction")) {
      direcaoMotor =
          doc["direction"].as<int>() < 0 ? -1 : 1;
    }

    if (doc.containsKey("running")) {
      motorLigado = doc["running"].as<bool>();

      if (motorLigado) {
        ultimoPasso = millis();
      } else {
        liberarMotor();
      }
    }

    responderStatus();
  });

  // Cores predefinidas ou valores RGB individuais
  servidor.on("/api/rgb", HTTP_POST, []() {
    StaticJsonDocument<256> doc;

    if (deserializeJson(doc, servidor.arg("plain"))) {
      erroJSON("JSON invalido");
      return;
    }

    if (doc.containsKey("color")) {
      String cor = doc["color"].as<String>();
      cor.toLowerCase();

      if (cor != "red" &&
          cor != "green" &&
          cor != "blue" &&
          cor != "white" &&
          cor != "yellow" &&
          cor != "cyan" &&
          cor != "magenta" &&
          cor != "off") {
        erroJSON("Cor nao reconhecida");
        return;
      }

      selecionarCor(cor);
    }

    bool rgbAlterado = false;

    if (doc.containsKey("red")) {
      vermelho = constrain(doc["red"].as<int>(), 0, 255);
      rgbAlterado = true;
    }

    if (doc.containsKey("green")) {
      verde = constrain(doc["green"].as<int>(), 0, 255);
      rgbAlterado = true;
    }

    if (doc.containsKey("blue")) {
      azul = constrain(doc["blue"].as<int>(), 0, 255);
      rgbAlterado = true;
    }

    if (rgbAlterado) {
      corAtual = "custom";
      luzLigada = true;
    }

    aplicarRGB();
    responderStatus();
  });

  // Brilho geral de 0 a 100%
  servidor.on("/api/brightness", HTTP_POST, []() {
    StaticJsonDocument<128> doc;

    if (deserializeJson(doc, servidor.arg("plain")) ||
        !doc.containsKey("brightness")) {
      erroJSON("Informe brightness entre 0 e 100");
      return;
    }

    brilho = constrain(
      doc["brightness"].as<int>(),
      0,
      100
    );

    aplicarRGB();
    responderStatus();
  });

  // Interruptor geral da iluminacao
  servidor.on("/api/light", HTTP_POST, []() {
    StaticJsonDocument<128> doc;

    if (deserializeJson(doc, servidor.arg("plain")) ||
        !doc.containsKey("on")) {
      erroJSON("Informe on como boolean");
      return;
    }

    bool ligar = doc["on"].as<bool>();

    if (ligar) {
      // Se nao houver cor selecionada, liga em branco.
      if (vermelho == 0 && verde == 0 && azul == 0) {
        vermelho = 255;
        verde = 255;
        azul = 255;
        corAtual = "white";
      }

      luzLigada = true;
    } else {
      // Preserva os valores RGB ao desligar.
      luzLigada = false;
    }

    aplicarRGB();
    responderStatus();
  });

  servidor.onNotFound([]() {
    servidor.send(
      404,
      "application/json",
      "{\"error\":\"Rota nao encontrada\"}"
    );
  });
}

// --------------------------------------------------
// Inicializacao
// --------------------------------------------------

void setup() {
  Serial.begin(115200);

  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(IN3, OUTPUT);
  pinMode(IN4, OUTPUT);

  pinMode(LED_R, OUTPUT);
  pinMode(LED_G, OUTPUT);
  pinMode(LED_B, OUTPUT);

  // PWM de 0 a 255
  analogWriteRange(255);
  analogWriteFreq(1000);

  liberarMotor();
  luzLigada = false;
  aplicarRGB();

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  Serial.print("Conectando ao Wi-Fi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }

  Serial.println();
  Serial.print("IP: ");
  Serial.println(WiFi.localIP());

  if (MDNS.begin("linkio-esp8266")) {
    MDNS.addService("http", "tcp", 80);
    Serial.println("mDNS iniciado: linkio-esp8266.local");
  }

  configurarRotas();
  servidor.begin();

  Serial.println("Servidor HTTP iniciado");
}

void loop() {
  servidor.handleClient();
  MDNS.update();
  atualizarMotor();
}
