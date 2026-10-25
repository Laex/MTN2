{ The screensaver subsystem (sharks swimming over a black screen).

  It is built by default. To build the program without it, either remove the
  dot below, or add NO_ASCII_SHARKS to the conditional defines of the project
  (Project Options > Delphi Compiler > Conditional defines). Without the
  subsystem the screensaver never starts, its menu cell and its entry in the
  Interface dialog do nothing, and none of the other units of this folder are
  compiled. }

{.$DEFINE NO_ASCII_SHARKS}

{$IFNDEF NO_ASCII_SHARKS}
  {$DEFINE MTN_ASCII_SHARKS}
{$ENDIF}
