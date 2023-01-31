/***  Volos' Room: Temperature, Humidity and Carbon Monoxide sensors ***/
// Measure temperature, humidity and CO levels in a room.

#include <WiFi.h>
#include <WiFiClient.h>
#include <DHT.h>
#include <MQUnifiedsensor.h>
#include "ThingSpeak.h"

// Definitions for WiFi connection
const char* ssid = "";				// Enter WiFi Name
const char* pwd = ""; 				// EnterWiFi Password
WiFiClient client;
// Definitions for ThingSpeak connection
const char* server = "api.thingspeak.com";  // ThingSpeak communication address
unsigned long chanID = 1993597;		// ThingSpeak channedl ID
const char* apiKey = "";    // ThingSpeak API key
// Definitions for DHT library
#define DHTPIN 21					// DHT pin
#define DHTTYPE DHT11				// DHT type
DHT dht(DHTPIN, DHTTYPE);
// Definitions for MQ7 library
#define Board ("ESP-32")
#define Pin (36)					// MQ7 analog pin
#define Type ("MQ-7")
#define Voltage_Resolution (3.3)	// ESP-32 Voltage: 3V3
#define ADC_Bit_Resolution (12)		// ESP-32 bit resolution. Source: https://randomnerdtutorials.com/esp32-adc-analog-read-arduino-ide/
#define RatioMQ7CleanAir (27.5)		// Clean air, according to MQ7 Sensitivity Characteristic Curve: RS / R0 = 27.5 ppm
MQUnifiedsensor MQ7(Board, Voltage_Resolution, ADC_Bit_Resolution, Pin, Type);
int mq7_digital = 19;				// MQ7 digital pin
// Definition for LED
const int ledPin = 5;				// LED pin

void setup() {
  Serial.begin(9600);
  dht.begin();						// Start DHT11
  MQ7.setRegressionMethod(1);		// Set MQ7's CO calculation method: ppm = A * ratio^B
  MQ7.setA(36974);					// Set A for the CO calculation
  MQ7.setB(-3.109);					// Set B for the CO calculation
  MQ7.init();						// Start MQ7
  pinMode(mq7_digital, INPUT);
  //pinMode(ledPin, OUTPUT);
  ThingSpeak.begin(client);			// Start ThingSpeak connection
  Serial.println("Connecting to ");
  Serial.println(ssid);
  WiFi.begin(ssid, pwd);			// Start WiFi connection
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.print(".");
  }
  Serial.println("");
  Serial.println("WiFi connected!");

  /*** MQ7 sensor Calibration ***/ 
  /* Explanation from "MQUnifiedsensor" library: 
  In this routine the sensor will measure the resistance of the sensor, supposedly before being pre-heated and on clean air, setting up R0 value.
  It is recommended executing this routine only on setup() in laboratory conditions.
  There is no need to be executed on each restart, R0 value can be loaded from eeprom.
  Acknowledgements: https://jayconsystems.com/blog/understanding-a-gas-sensor
  */
  Serial.print("Calibrating please wait.");
  float calcR0 = 0;
  for(int i = 1; i <= 10; i ++)
  {
    MQ7.update();					// Update data through reading the voltage from MQ7's analog pin
    calcR0 += MQ7.calibrate(RatioMQ7CleanAir);
    Serial.print(".");
  }
  MQ7.setR0(calcR0/10);
  Serial.println("  done!.");
  if (isinf(calcR0)) {
    Serial.println("Warning: Conection issue, R0 is infinite (Open circuit detected). Please check your wiring and supply"); while(1);
  }
  if (calcR0 == 0) {
    Serial.println("Warning: Conection issue found, R0 is zero (Analog pin shorts to ground). Please check your wiring and supply"); while(1);
  }
}

void loop() {
  // DHT data readings
  int hmdt = dht.readHumidity();	// Read humidity
  int tmprtr_C = dht.readTemperature();     // Read temperature as Celsius (the default)
  float hi_C = dht.computeHeatIndex(tmprtr_C, hmdt, false); // Compute heat index in Celsius (isFahreheit = false)
  //float tmprtr_F = dht.readTemperature(true); // Read temperature as Fahrenheit (isFahrenheit = true)
  //float hi_F = dht.computeHeatIndex(tmprtr_F, hmdt);  // Compute heat index in Fahrenheit (the default)

  // MQ7 data readings
  MQ7.update();
  float CO_a = MQ7.readSensor();
  int CO_d = digitalRead(mq7_digital);

  // Check if any DHT reads failed, print error and exit early (to try again).
  if (isnan(hmdt) || isnan(tmprtr_C)) {
    Serial.println(F("Failed to read from DHT sensor!"));
    return;
  }
  // Check if MQ7 any reads failed, print error and exit early (to try again).
  if (isnan(CO_a) || isnan(CO_d)) {
    Serial.println(F("Failed to read from MQ7 sensor!"));
    return;
  }  

  // Connect to ThingSpeak and send sensor data
  ThingSpeak.setField(1, tmprtr_C);
  ThingSpeak.setField(2, hmdt);
  ThingSpeak.setField(3, hi_C);
  ThingSpeak.setField(4, CO_a);

  // Write to the ThingSpeak channel
  int x = ThingSpeak.writeFields(chanID, apiKey);
  if(x == 200){
    Serial.println("ThingSpeak Channel updated successfully.");
  }
  else{
    Serial.println("Problem updating channel. HTTP error code " + String(x));
  }

  /* // LED light for high CO levels
  if (CO_a > 10) {
    Serial.println("CO level is above normal (more than 10 ppm!");
    digitalWrite (ledPin, HIGH);  // turn on the LED
    delay(1000);
    digitalWrite (ledPin, LOW);   // turn off the LED
  }
  else {
    Serial.println("CO level is normal (below 10 ppm)");
  }
  delay(100);
  */  
  // Print DHT data to serial monitor
  Serial.print("Temperature: ");
  Serial.print(tmprtr_C);
  Serial.print(" C   Humidity: ");
  Serial.print(hmdt);
  Serial.print("%   Heat Index: ");
  Serial.print(hi_C);
  Serial.print(" C   ||   ");
  // Print MQ7 data to serial monitor
  Serial.print("Gas Sensor: ");
  Serial.print(CO_a);
  Serial.println(" ppm");
  //Serial.print("Gas Class: ");
  //Serial.println(CO_d);
  delay(30000);						// Wait 30 seconds between measurements.
}