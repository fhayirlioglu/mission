#include <WiFi.h>
#include <WiFiClient.h>
#include <ArduinoJson.h>

// -----------------------------------------------------------------------------
// ----- Sızıntı Sensörü ve LED Ayarları (Örnek Koda Uyumlu) -----
const int LED_PIN = 13;        // Sızıntı durumunu gösteren LED pini
const int LEAK_SENSOR_PIN = 2; // Sızıntı sensörünün bağlı olduğu GPIO pini
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// ----- BMS Wi-Fi ve Web Sunucusu Ayarları -----
const char *bms_ssid = "GLORIA_34:B7:DA:72:56:C0";
const char *bms_password = "gloria123456";
const char *bms_host = "192.168.4.1";
const int bms_port = 80;
const char *bms_path = "/bqEvents";
// -----------------------------------------------------------------------------

const size_t jsonDocumentCapacity = 4096;
const size_t outputJsonCapacity = 384 + 64;

WiFiClient client;

float g_pack_voltage_V = 0.0f;
int g_soc_percent = 0;
float g_current_A = 0.0f;
float g_total_voltage_vsum_V = 0.0f;
float g_temperature_C = -273.15f;
float g_avg_cell_voltage_V = 0.0f;
String g_leak_status = "none";

const int lut_size = 9;
const float voltage_points[lut_size] = {2.80f, 3.20f, 3.40f, 3.60f, 3.75f, 3.87f, 3.98f, 4.10f, 4.20f}; // Volt
const int soc_points[lut_size] = {0, 10, 25, 50, 70, 80, 90, 95, 100};                                  // Yüzde (%)

int estimateSoCFromVoltage(float avg_cell_voltage_V)
{
  if (avg_cell_voltage_V <= voltage_points[0])
    return soc_points[0];
  if (avg_cell_voltage_V >= voltage_points[lut_size - 1])
    return soc_points[lut_size - 1];
  for (int i = 0; i < lut_size - 1; i++)
  {
    if (avg_cell_voltage_V >= voltage_points[i] && avg_cell_voltage_V < voltage_points[i + 1])
    {
      float volt_range = voltage_points[i + 1] - voltage_points[i];
      float soc_range = soc_points[i + 1] - soc_points[i];
      float voltage_offset = avg_cell_voltage_V - voltage_points[i];
      if (volt_range == 0)
        return soc_points[i];
      return soc_points[i] + (int)((voltage_offset / volt_range) * soc_range);
    }
  }
  return soc_points[lut_size - 1];
}

void setup()
{
  // USB Seri İletişimini Başlat (Orin ve debug için)
  // Örnek kod 9600 kullanıyor, ancak Orin ile daha hızlı iletişim için 115200 daha iyi olabilir.
  // Şimdilik örnekteki gibi 9600 bırakıyorum, gerekirse 115200'e çevirebilirsiniz.
  // Python kodunuzdaki baud hızını da buna göre ayarlamayı unutmayın!
  Serial.begin(115200); // Örnekteki 9600 yerine 115200 devam edelim.
  delay(1000);

  // Sızıntı sensörü ve LED pinlerini ayarla (Örnek koda uyumlu)
  pinMode(LED_PIN, OUTPUT);
  pinMode(LEAK_SENSOR_PIN, INPUT);                                          // INPUT_PULLUP yerine INPUT
  Serial.println("Blue Robotics SOS Leak Sensor Example (Entegre Edildi)"); // Bu mesaj Orin'e de gidecek

  Serial.println();
  Serial.print("WiFi Agina Baglaniliyor: ");
  Serial.println(bms_ssid);

  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  WiFi.begin(bms_ssid, bms_password);

  int retries = 0;
  Serial.print("Baglaniyor");
  while (WiFi.status() != WL_CONNECTED && retries < 30)
  {
    delay(500);
    Serial.print(".");
    retries++;
  }

  if (WiFi.status() == WL_CONNECTED)
  {
    Serial.println("\nWi-Fi baglantisi basarili!");
    Serial.print("ESP32 IP adresi: ");
    Serial.println(WiFi.localIP());
    Serial.println("--- BMS Veri Gonderimi Basliyor (USB) ---");
  }
  else
  {
    Serial.println("\nWi-Fi baglantisi kurulamadi.");
    Serial.println("ESP32 yeniden baslatilacak...");
    delay(1000);
    ESP.restart();
  }
}

void sendParsedDataToOrin()
{
  StaticJsonDocument<outputJsonCapacity> docToSend;
  docToSend["pack_voltage"] = g_pack_voltage_V;
  docToSend["soc_estimated"] = g_soc_percent;
  docToSend["current"] = g_current_A;
  docToSend["total_voltage_vsum"] = g_total_voltage_vsum_V;
  docToSend["temperature"] = g_temperature_C;
  docToSend["avg_cell_voltage"] = g_avg_cell_voltage_V;
  docToSend["leak_status"] = g_leak_status;
  String outputJsonString;
  serializeJson(docToSend, outputJsonString);
  Serial.println(outputJsonString);
}

void connectToBmsAndGetData()
{
  if (WiFi.status() != WL_CONNECTED)
    return;
  if (!client.connect(bms_host, bms_port))
    return;

  client.print(String("GET ") + bms_path + " HTTP/1.1\r\n" +
               "Host: " + bms_host + "\r\n" +
               "Connection: keep-alive\r\n" +
               "Accept: text/event-stream\r\n" +
               "\r\n");

  unsigned long headers_timeout = millis();
  while (client.connected() && !client.available() && millis() - headers_timeout < 5000)
    delay(10);

  while (client.connected() && client.available())
  {
    String line = client.readStringUntil('\n');
    if (line == "\r" || line.length() == 0)
      break;
  }

  String currentLine = "";
  unsigned long data_stream_start_time = millis();

  while (client.connected() && (millis() - data_stream_start_time < 5000))
  {
    if (client.available())
    {
      char c = client.read();
      currentLine += c;
      if (c == '\n')
      {
        if (currentLine.startsWith("data: "))
        {
          String jsonData = currentLine.substring(strlen("data: "));
          jsonData.trim();
          if (jsonData.length() > 0 && jsonData.startsWith("{") && jsonData.endsWith("}"))
          {
            DynamicJsonDocument doc(jsonDocumentCapacity);
            DeserializationError error = deserializeJson(doc, jsonData);
            if (!error)
            {
              if (doc.containsKey("measurements"))
              {
                JsonObject measurements = doc["measurements"];
                g_pack_voltage_V = measurements["vpack"].as<float>() / 1000.0f;
                if (measurements.containsKey("curr") && measurements["curr"].is<JsonObject>())
                {
                  JsonObject current_obj = measurements["curr"];
                  g_current_A = current_obj["CC1"].as<float>() / 1000.0f;
                }
                else
                {
                  g_current_A = 0.0f;
                }
                if (measurements.containsKey("vsum"))
                {
                  g_total_voltage_vsum_V = measurements["vsum"].as<float>() / 1000.0f;
                }
                else
                {
                  g_total_voltage_vsum_V = 0.0f;
                }
                if (measurements.containsKey("temps") && measurements["temps"].is<JsonArray>())
                {
                  JsonArray temps = measurements["temps"];
                  if (temps.size() > 0)
                  {
                    g_temperature_C = temps[0].as<float>() / 10.0f;
                  }
                  else
                  {
                    g_temperature_C = -273.15f;
                  }
                }
                else
                {
                  g_temperature_C = -273.15f;
                }
                if (measurements.containsKey("vcells") && measurements["vcells"].is<JsonArray>())
                {
                  JsonArray vcells = measurements["vcells"];
                  float sum_cell_voltages_mV = 0;
                  int valid_cell_count = 0;
                  for (int i = 0; i < vcells.size() && i < 12; i++)
                  {
                    int cell_mV = vcells[i].as<int>();
                    if (cell_mV > 2700 && cell_mV < 4300)
                    {
                      sum_cell_voltages_mV += cell_mV;
                      valid_cell_count++;
                    }
                  }
                  if (valid_cell_count > 0)
                  {
                    g_avg_cell_voltage_V = (sum_cell_voltages_mV / valid_cell_count) / 1000.0f;
                    g_soc_percent = estimateSoCFromVoltage(g_avg_cell_voltage_V);
                  }
                  else
                  {
                    g_avg_cell_voltage_V = 0.0f;
                    g_soc_percent = 0;
                  }
                }
                else
                {
                  g_avg_cell_voltage_V = 0.0f;
                  g_soc_percent = 0;
                }
                // Artık BMS verileri global değişkenlerde, sendParsedDataToOrin() loop'ta çağrılacak
              }
            }
          }
        }
        currentLine = "";
      }
    }
    else
    {
      delay(1);
    }
  }
  client.stop();
}

void loop()
{
  // Sızıntı Sensörünü Oku (Örnek koda uyumlu mantık)
  int leakValue = digitalRead(LEAK_SENSOR_PIN); // leakValue 0 (LOW) veya 1 (HIGH) olacak
  digitalWrite(LED_PIN, leakValue);             // LED'i sızıntı durumuna göre ayarla (HIGH ise yanar)

  if (leakValue == HIGH)
  { // Örnek kodda "leak == 1" sızıntı demekti, bu genellikle HIGH anlamına gelir
    g_leak_status = "detected";
    Serial.println("Leak Detected! (Bu mesaj Orin'e de gidecek)"); // Örnekteki gibi mesaj bas
  }
  else
  {
    g_leak_status = "none";
  }

  // Wi-Fi bağlantısını kontrol et ve BMS verilerini global değişkenlere al
  if (WiFi.status() == WL_CONNECTED)
  {
    connectToBmsAndGetData();
  }
  else
  {
    WiFi.disconnect();
    WiFi.begin(bms_ssid, bms_password);
    int wifi_retries = 0;
    while (WiFi.status() != WL_CONNECTED && wifi_retries < 10)
    {
      delay(500);
      wifi_retries++;
    }
    if (WiFi.status() == WL_CONNECTED)
    {
      Serial.println("\n--- Wi-Fi Yeniden Baglandi (USB) ---");
    }
  }

  // Tüm güncel verileri (BMS + Sızıntı durumu) periyodik olarak Orin'e gönder
  sendParsedDataToOrin();

  delay(1000); // Ana döngünün genel sıklığı
}
