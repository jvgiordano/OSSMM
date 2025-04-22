---
title: "Safety and Data Privacy"
permalink: /safet-and-data/
date: 2025-04-23T00:26:20+01:00
class: wide
---

## Safety Considerations

User safety was a fundamental priority throughout the development of OSSMM. 
The design incorporates several important safety features:

* **Low-voltage electronics**: All electronic components are commercially 
available, hobbyist-grade parts commonly used in wearable maker projects. The 
system operates entirely on low voltage (3.3V), minimizing electrical risks.

* **Limited battery capacity**: The small-capacity battery (120-220 mAh) 
significantly reduces potential risks associated with battery malfunctions.

* **Non-invasive sensors**: With the exception of the pulse sensor, all 
measurement systems are passive. The pulse sensor uses photoplethysmography 
(PPG) - the same light-based technology found in consumer smartwatches - which
emits only low-intensity light to detect blood flow beneath the skin. At no
point is current injected into the body

* **Biocompatible materials**: We selected specific 3D printing filaments based 
on their published safety data to ensure skin contact compatibility. Safety 
data sheets for all components and filaments are included in this repository 
for your reference.

While we've made every effort to design a safe system, users assume 
responsibility for their implementation. We cannot be held liable for any use,
misuse, or adverse events resulting from the construction or operation of an 
OSSMM system. It remains the user's responsibility to properly assemble their
device using appropriate components from reputable sources and to ensure proper
operation. This is not a medical device.

## Data Privacy and Security

OSSMM was designed with data protection in mind: 

* **Secure BLE connection**: The app-to-device BLE connection requires 
verification of 3 unique UUIDs before data transmission occurs.

* **User-customizable security**: Each user can modify these UUID values to 
create their own unique security "profile".

* **Local data storage**: All data collected by OSSMM is stored locally on a 
companion Android device in a dedicated "/OSSMM" directory. No data is 
automatically transmitted to external servers or cloud services, unless you 
choose to do so.

* **Device security recommendations**: Due to the nature of sleep and 
physiological data, we recommend that companion devices used with OSSMM be 
secured with PIN codes or other access controls.

---
*Current Version: V1.0.4*
