

































































































































































































































// Pinout for controlling the motors:
byte pinVib[] = {3, 4, 5, 6, 9, 10};
byte nPinVib = sizeof(pinVib) / sizeof(pinVib[0]);

// Set debug to 1 to receive debugging information via the serial port:
bool debug = 1;

// What the Teensy does is controlled externally by writing a byte to the serial port,
// which sets the current "state" of the Teensy as defined by the switch-case statement
// in the main loop.
byte state = 0;

// Dead man timer: unless we receive a serial signal, we will default to state 0
// after a few seconds to endsure the motors won't run forever:
unsigned long deadManTimeout = 5000;
unsigned long deadManTimer;

void setup() {
  // Initialize motor pins:
  for (byte i = 0; i < nPinVib; i++)
  {
      pinMode(pinVib[i], OUTPUT);
  }

  // Initialize serial communication:
  Serial.begin(9600);
  while (!Serial) {
    ; // wait for serial port to connect. Needed for native USB port only
  }
  Serial.println("Serial communication started.");
}

void loop() {
  // First, check if the state has changed:    
  if (Serial.available() > 0) {
    state = Serial.read();
    printlnDebug("Received new state instruction.");
    
    // Reset dead man timer:
    deadManTimer = millis() + deadManTimeout;
  } else if (deadManTimer < millis()) {
    // Default to zero if the dead man timer expires:
    state = 0;
    printlnDebug("Waiting (state 0; dead man timer expired).");
  }

  switch(state) {
    case 0:
      // Waiting state:
      printlnDebug("Waiting (state 0).");
      switchAllVibOff();
      break;

    case 1:
    case 2:
    case 3:
    case 4:
    case 5:
    case 6:
      // Switch on the motor corresponding to the state number:
      char msg[100];
      sprintf(msg, "Executing state %d.", state);
      printlnDebug(msg);
      switchAllVibOff();
      analogWrite(pinVib[state-1], 255);
      break;

    case 99:
      // Test state:
      printlnDebug("Executing test state (99).");
      switchAllVibOff();
      break;

    default:
      printlnDebug("Unknown state. Defaulting to state 0.");
      state = 0;
      break;
  }
    
}

void switchAllVibOff() {
    for (byte i = 0; i < nPinVib; i++)
    {
        analogWrite(pinVib[i], 0);
    }
}

void printlnDebug(const char* msg){
  // Timer to limit the rate at which messages are printed:
  static unsigned long debugOutputTimer = 0.0;

  // Do print all state changes even if the timer has not yet expired:
  static byte prevState = 0;
  
  if (debug && ((debugOutputTimer < millis()) || (prevState != state))) {
    Serial.print("STATE: ");
    Serial.print(state, DEC);
    Serial.print("\t");

    Serial.print("MSG: ");
    Serial.println(msg);

    debugOutputTimer = millis()+1000;
    prevState = state;
  }
}
