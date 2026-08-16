# Individual vehicle speed bonus parameters

Vehicle `.dat` files may override the reference speed and maximum speed-related
payment used for cargo carried by that vehicle:

```text
speed_bonus_reference_percent=100
speed_bonus_max_percent=0
```

`speed_bonus_reference_percent` is the percentage of the current era and
waytype reference speed used to calculate the speed bonus. It accepts values
from 1 to 65535 and defaults to 100.

`speed_bonus_max_percent` caps the speed-related payment factor after the
vehicle reference speed has been applied. It accepts values from 0 to 65535;
zero, the default, means no vehicle-specific cap. The global
`bonus_basefactor` remains the lower limit.

For example, a city bus whose fare should be calculated against half of the
road reference speed and capped at 70% uses:

```text
speed_bonus_reference_percent=50
speed_bonus_max_percent=70
```

The parameters belong to the vehicle carrying the cargo. In a train, each
passenger or freight car therefore applies its own values; a locomotive with
no cargo does not affect the calculation.

MakeObj writes vehicle descriptor version 14 and stores both values for every
vehicle. When the parameters are omitted, their default values are stored.
Simutrans continues to read legacy version 13 vehicle descriptors, applying the
same defaults to them.
