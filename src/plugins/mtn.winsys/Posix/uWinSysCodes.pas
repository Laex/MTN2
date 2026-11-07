unit uWinSysCodes;

{ The Win32 error numbers the system plugin reports its results with. Windows
  declares them in Winapi.Windows; here they are numbers of their own, so the
  shared code reads the same on both systems. }

interface

const
  ERROR_INVALID_FUNCTION = 1;
  ERROR_FILE_NOT_FOUND = 2;
  ERROR_PATH_NOT_FOUND = 3;
  ERROR_ACCESS_DENIED = 5;
  ERROR_INVALID_PARAMETER = 87;
  ERROR_ALREADY_EXISTS = 183;
  ERROR_SERVICE_REQUEST_TIMEOUT = 1053;
  ERROR_SERVICE_DOES_NOT_EXIST = 1060;
  ERROR_PRIVILEGE_NOT_HELD = 1314;

implementation

end.
