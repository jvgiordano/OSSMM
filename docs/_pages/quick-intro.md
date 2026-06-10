---
title: "Quick Introduction"
permalink: /quick-intro/
date: 2025-05-16T00:26:20+01:00
classes: single
read_time: true
toc: true # Enable Table of Contents for this page
toc_sticky: true
---

# Welcome to OSSMM!

**OSSMM** (Open-Source Sleep Monitor and Modulator) is, to our knowledge, the first fully open-source wearable — open hardware and open software — that is purpose-built and for both sleep monitoring and modulation. Earlier open-source efforts combined the two, but depended on commercial headbands or general-purpose EEG research platforms rather than a self-contained, low-cost device.

<br>
# Who is it for?

OSSMM is for researchers and sleep enthusiasts in need of an affordable
and accurate sleep monitoring system. It's also for those who need a platform 
which can implement automated sleep modulation. 

Building your own OSSMM requires some basic-to-moderate electronics and 
3D printing knowledge. We provide resources for learning everything you need to
know, and a detailed Build Guide for assembling your own.

This is a great starter project for electronics and 3D printing. For first time
builders with basic background knowledge, assembly should take 4-6 hours for
the first unit. Those who are experienced can easily assemble a unit in under 2 
hours.

<br>
# Who made it?

The OSSMM project was developed as part of Jonny Giordano's thesis at the
Hamilton Institute at Maynooth University. 
 

<br>
# The Goal:
OSSMM was created to address the prohibitive entry cost into 
quality sleep research. By providing researchers and sleep enthusiasts with an
affordable platform that can be assembled locally, this accessible system 
promotes:

- Cost-effective large-scale, long-term sleep studies
- Data collection in participants' natural home environments
- Effective monitoring for under €40 per unit (as of 12/2024)[^note1]

**Most importantly, OSSMM enables sleep modulation experiments — filling a gap 
where no comparable off-the-shelf system currently exists.**


<br>
<div style="display: flex; flex-direction: row; align-items: flex-start;">
  <figure style="margin: 0; width: 42%;">
    <img src="{{ site.url }}/OSSMM/media/quick-intro/stretch.jpg" alt="Front view of OSSMM headband" style="width: 100%;">
    <figcaption style="text-align: center; font-style: italic; margin-top: 5px;">OSSMM Headband on display with strap fully stretched out.</figcaption>
  </figure>
  <figure style="margin: 0; width: 50%; margin-left: 4%;">
    <img src="{{ site.url }}/OSSMM/media/quick-intro/ports.jpg" alt="Back view of OSSMM headband" style="width: 100%;">
    <figcaption style="text-align: center; font-style: italic; margin-top: 5px;">Macro photo of OSSMM Headband. USB-C, LED port, ON/Reset switch, and microphone port are visible. €1 euro coin for size reference.</figcaption>
  </figure>
</div>
<br>

# What are "sleep monitoring" and "sleep modulation"?

<ins> Sleep monitoring </ins> is the recording of physiological signals to 
assess sleep duration, quality, and architecture. This typically involves sleep 
staging - the categorization of sleep-wake states. Five-stage systems include N1, 
N2, N3, REM (Rapid Eye Movement), and Wake states, while four-stage systems use 
Deep Sleep, Light Sleep, REM, and Wake.


<ins> Sleep modulation </ins> is the intentional use of non-invasive techniques 
to modify, regulate, or enhance sleep architecture and target specific sleep 
signatures. Goals include improving sleep quality, optimizing sleep stages, and 
enhancing associated cognitive and physiological functions. Common techniques 
include acoustic, optical, and electrical stimulation, and physical arousal.

# Understanding the Build Process

Creating your own OSSMM system involves five main steps that follow our detailed build guides:

**Step 1: 3D Printables** - Print the receiver using TPU filament and the electronics case using PLA. Print times will depend on your printer and experience level.

**Step 2: Electronics Assembly** - Standard soldering to connect the electronic components together and install them in the 3D printed case. This should take no more than 4-6 hours for a beginner. Experienced OSSMM builders can assemble comfortably under 50 minutes.

**Step 3: Major Parts Assembly** - Combine the three principal components: headband, receiver, and electronic case. This should take no more than an hour.

**Step 4: Software** - Upload code to the microcontroller and install the Android app. This should take no more than an hour.

**Step 5: Final Checks** - Systematic testing to verify all sensors function correctly. This should take no more than 30 minutes.

The modular design means you can work on these steps independently or 
collaborate with others who have different expertise in 3D printing, electronics,
or software. We estimate a first build to require ~2 Days, including over night
print times.

# Key Design Features:

* **Reusable silicone wet-dry electrodes** - no conductive gel needed
* **Quick-change parts** - easy repair and hygiene
* **Battery powered with no exposed wiring** - 23+ hour run-time
* **Fully open-source hardware designs and software code**
  - Complete access for researcher modifications
  - Full transparency of sleep staging algorithms and hardware code
  
<br>

# Device Overview (V1.0.4)

OSSMM consists of a wearable headband that collects physiological data
and transmits it wirelessly via Bluetooth Low Energy (BLE) to a dedicated 
Android application. Only Android is supported at this time.

<div style="display: flex; flex-direction: row; align-items: flex-start;">
  <figure style="margin: 0; width: 45%;">
    <img src="{{ site.url }}/OSSMM/media/quick-intro/front.jpg" alt="Front view of OSSMM headband" style="width: 100%;">
    <figcaption style="text-align: center; font-style: italic; margin-top: 5px;">Fig 1: Front of the OSSMM headband compared with a €1 coin.</figcaption>
  </figure>
  <figure style="margin: 0; width: 50%; margin-left: 4%;">
    <img src="{{ site.url }}/OSSMM/media/quick-intro/back.jpg" alt="Back view of OSSMM headband" style="width: 100%;">
    <figcaption style="text-align: center; font-style: italic; margin-top: 5px;">Fig 2: Back of the OSSMM headband, with the silicone electrodes and PPG sensor visible.</figcaption>
  </figure>
</div>
<br>


## Benefits:

* **Minimal Design**: Just 11 components (excluding wires)
* **Comfortable Electrodes**: Elastic band with integrated silicone wet-dry electrodes (commercial heart rate monitor strap)
* **Standard Electronics**: Four readily available off-the-shelf circuit boards
* **Locally Manufacturable Housing**: 3D printable design
* **Convenient Power**: USB-C rechargeable battery for easy charging


## Technical Specifications:

* **Dimensions: 79.1 x 47.2 x 31 mm**  (3.12 x 1.86 x 1.22 in)
* **Weight: 76.6 grams** ( or 2.7 ounces with a 200 mAh battery)
* **Sampling Frequency: +250 Hz** ( 500MB of data per 8 hour recording)
* **Battery: 120-220 mAh** (est. 15-25+ hour run time, sleep monitoring only)

## Physiological Measurements:

* **Brain Activity:** Frontal Electroencephalography (EEG)
* **Eye Movement:** Electrooculography (EOG)
* **Head Movement:** Via onboard Inertial Measurement Unit (IMU)
* **Heart Rhythm:** Photoplethysmography (PPG)

*Note: While the hardware includes a microphone for sound data collection, 
this feature is not activated in version 1.0.4.*

## Quick App Demo

<figure style="text-align: center; width: 100%; display: block; margin: 0 auto;">
  <img src="{{ site.url }}/OSSMM/media/quick-intro/quick-demo.gif" alt="quick-demo" style="width: 30%; display: block; margin: 0 auto;">
  <figcaption style="text-align: center; font-style: italic; margin-top: 5px; display: block;">Short Demo of OSSMM app. Real-time app usage is smoother than can be shown in this GIF.</figcaption>
</figure>
<br>

# Performance:

OSSMM promises to offer more accurate sleep staging than many commercial wearables 
(smart watches, rings) at a fraction of the price. 

*Note: OSSMM is currently under technical validation for 4-stage sleep classification.*

# Sleep Modulation Capabilities:

OSSMM V1.0.4 incorporates a commercial off-the-shelf vibration motor 
(similar to those in mobile phones) as a stimulus mechanism for sleep 
modification experiments. The vibration motor was chosen as the reference 
stimulus because:

1. It demonstrates the system's robust power handling (60+ mA during operation)
2. It proves the platform can easily accommodate other stimulus methods 
including speakers, LEDs, tDCS, and tACS

Future versions aim to analyze sleep data in near-real-time 
(within 30-60 seconds) to potentially trigger sleep modulation 
based on detected sleep stages.

<br>
# Start Building Now

We recommend reviewing the 
[Getting Started](https://jvgiordano.github.io/OSSMM/getting-started/) before
beginning your OSSMM build. This page contains detailed information about OSSMM
and all the pre-requisites.

To build your own OSSMM system, follow these pages in order:

1. [3D Printables](https://jvgiordano.github.io/OSSMM/printables) - Print out the printable components
2. [Electronics Assembly Guide](https://jvgiordano.github.io/OSSMM/electronics-assembly/) - Combine the electronics and 3D printed case
3. [Major Parts Assembly](https://jvgiordano.github.io/OSSMM/final-assembly/) - Assemble the 3 principal components: headband, receiver, electronic case
4. [Software](https://jvgiordano.github.io/OSSMM/software/) - Upload OSSMM code to the MCU (Microcontroller), and install the OSSMM apk (app file) on your Android device
5. [Final Checks & Completion](https://jvgiordano.github.io/OSSMM/final-checks) - Verify your OSSMM system collects data as intended

**Additional Notes:**

[^note1]: V1.0.4 requires an Android device with the dedicated companion app to work. While currently requiring an Android device, any platform supporting high-priority BLE transmission could potentially work (iPhone, Raspberry Pi, etc.). The cost estimate does not include the Android device.
