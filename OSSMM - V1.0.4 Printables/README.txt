# OSSMM 3D Printable Hardware Components

These 3D design files are part of the OSSMM (Open-Source Sleep Monitor and 
Modulator) project developed at the Hamilton Institute, Maynooth University.

## Components Included

This directory contains the following 3D printable components:

1. **Receiver** (TPU flexible filament)
   - Holds the PulseSensor
   - Provides comfortable interface between electronics and forehead
   - Allows strap threading

2. **Electronics Case Bottom** (PLA rigid filament)
   - Houses the microcontroller, battery, and sensor boards
   - Provides electronics protection

3. **Electronics Case Lid** (PLA rigid filament)
   - Snap-fastener electrode mounting points
   - Completes the electronics enclosure

## Copyright and License

**Copyright (C) 2022-2025 Maynooth University**

Developed by: Jonny Giordano  
Institution: Hamilton Institute, Maynooth University  

These hardware designs are licensed under the **CERN Open Hardware License 
Version 2 - Strongly Reciprocal (CERN-OHL-S v2)**.

### What This License Means

You are free to:
- Use these designs for any purpose (commercial or non-commercial)
- Modify these designs
- Manufacture products based on these designs
- Distribute these designs and products made from them

**However**, if you manufacture and distribute products based on these designs, 
or if you distribute modified versions of these designs, you **must**:
- Make the complete design documentation available
- License your documentation under CERN-OHL-S v2
- Provide clear attribution to the original designs
- Include prominent notices about modifications you've made

This strong reciprocal provision ensures that improvements and derivatives 
remain open and available to the research community.

### Full License Text

See the `LICENSE-HARDWARE.txt` file in this directory for the complete 
CERN-OHL-S v2 license text, or visit:  
https://ohwr.org/cern_ohl_s_v2.txt

For more information about the CERN Open Hardware License:  
https://ohwr.org/project/cernohl/wikis/home

## Available Formats

### STL Files (Manufacturing-Ready)
The STL files in this directory are ready to be imported into your slicer 
software and printed. These are the "manufacturing files" as defined by 
CERN-OHL-S.

### Source CAD Files (Design Documentation)
The original parametric CAD files are available in OnShape at:  
https://cad.onshape.com/documents/e164190f177bb3416611691f/w/3a7e0f620951f19ab875bfa1/e/582f79c9755c0593cd9a0582?renderMode=0&uiState=69383284364f5b07cb820b18

The OnShape CAD project represents the "Documentation" as defined by 
CERN-OHL-S. If you modify these designs, you should ideally make your 
modifications in the CAD source and generate new STL files, though 
modifications directly to STL files are also permitted.

## Manufacturing Specifications and Recommendations

### Receiver
- **Material**: TPU-85 or TPU-95 (Thermoplastic Polyurethane)
  - TPU-85 recommended for maximum comfort
  - TPU-95 acceptable and easier to print
- **Infill**: 8% gyroid pattern (other percentages may be used based on your filament and print settings.)
- **Layer Height**: 0.2mm recommended
- **Print Speed**: Slow (20-30 mm/s recommended for TPU)
- **Support**: Recommended, use "snug" supports
- **Bed Adhesion**: Raft or brim recommended
- **Print Time**: Approximately 6-7 hours (Prusa MK3S+ reference)
- **Post-Processing**: Remove supports carefully, ensure smooth rear surface

**Important Note on Infill**: The 8% gyroid infill is essential for creating 
an "air cushion" effect that provides comfort without collapse. Higher infill 
percentages will make the receiver too rigid and uncomfortable. Lower 
percentages may cause structural failure.

### Electronics Case (Bottom and Lid)
- **Material**: PLA (Polylactic Acid)
- **Print Quality**: Highest quality settings your printer supports
- **Layer Height**: 0.15mm or finer recommended for detail
- **Infill**: Standard (20-30%)
- **Support**: Required for internal structures
- **Print Time**: Approximately 2-3 hours combined (Prusa MK3S+ reference)
- **Post-Processing**: Remove supports, clean any stringing, verify USB port clearance

## Safety Considerations

### Material Selection
We recommend using materials with documented biocompatibility data for 
components that make prolonged skin contact (primarily the TPU receiver).

We used:
- **TPU**: Siraya Tech Flex TPU-85A (biocompatibility certifications available)
- **PLA**: Prusament PLA (safety data sheets available)

Safety data sheets for recommended materials are available in the 
`/OSSMM-Data-and-Safety-docs/` directory of the main repository.

### Print Quality
Ensure prints are structurally sound with no layer delamination, especially 
for the receiver which experiences mechanical stress during use.

## Assembly

These 3D printed components are part of the larger OSSMM system. For complete 
assembly instructions showing how these parts integrate with the electronics 
and strap, see:  
https://jvgiordano.github.io/OSSMM/final-assembly/

## Testing and Validation

After printing, verify:
- Receiver slots accept the PulseSensor without excessive force
- Strap channels allow smooth strap threading
- Electronics case properly houses all components
- USB port is accessible and functional
- Snap-fastener mounting points are structurally sound

## Citation

If you use or modify these designs in your research, please cite:
```
Giordano, J. (2025). OSSMM: Open-Source Sleep Monitor and Modulator 
- Hardware Designs. Maynooth University. 
https://github.com/jvgiordano/OSSMM
```

A formal academic publication describing OSSMM is forthcoming.

## Modifications and Contributions

We welcome improvements and modifications to these designs. If you create 
modified versions, please:
1. Clearly document what you changed and why
2. Share your modifications under CERN-OHL-S v2
3. Consider submitting a pull request to this repository
4. Update the version markings on your modified designs

## Acknowledgments

This project was developed as part of doctoral research at the Hamilton 
Institute, Maynooth University, with financial support from Taighde Éireann – 
Research Ireland under Grant number 18/CRT/6049.

---

**Version**: 1.0.4  
**Last Updated**: [Current Date]  
**License**: CERN-OHL-S v2
```