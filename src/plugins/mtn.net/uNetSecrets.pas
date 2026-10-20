unit uNetSecrets;

{ Protects the passwords and passphrases a session keeps in the plugin's
  settings. On Windows the secret is sealed with the data protection API for
  the signed-in user (only that user on that machine can open it). Other
  systems have no store the plugin can rely on, so nothing is saved there and
  the user is asked at connection time. }

interface

/// <summary>True when ProtectSecret keeps secrets on this system.</summary>
function SecretsAvailable: Boolean;
/// <summary>The sealed form of AText, text safe to put into a settings file;
/// '' when it cannot be sealed.</summary>
function ProtectSecret(const AText: string): string;
/// <summary>Opens what ProtectSecret made. False when it is not ours, is
/// sealed for another user or is damaged.</summary>
function UnprotectSecret(const ASealed: string; out AText: string): Boolean;

implementation

uses
  System.SysUtils, System.NetEncoding
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF};

const
  cPrefix = 'dpapi:';

{$IFDEF MSWINDOWS}
type
  PDataBlob = ^TDataBlob;
  TDataBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;

function CryptProtectData(pDataIn: PDataBlob; szDataDescr: PWideChar; pOptionalEntropy: PDataBlob;
  pvReserved: Pointer; pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PDataBlob): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptProtectData';
function CryptUnprotectData(pDataIn: PDataBlob; ppszDataDescr: PPWideChar; pOptionalEntropy: PDataBlob;
  pvReserved: Pointer; pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PDataBlob): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptUnprotectData';

const
  CRYPTPROTECT_UI_FORBIDDEN = 1;
  // Mixed into the key so another program of the same user cannot open it by accident.
  cEntropy: AnsiString = 'MTN2.net.session';
{$ENDIF}

function SecretsAvailable: Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := True;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function ProtectSecret(const AText: string): string;
{$IFDEF MSWINDOWS}
var
  Plain, Entropy, Sealed: TDataBlob;
  Bytes, Out_: TBytes;
  Enc: TBase64Encoding;
begin
  Result := '';
  // Nothing to seal: an empty secret is not saved at all.
  if AText = '' then
    Exit;
  Bytes := TEncoding.UTF8.GetBytes(AText);
  Plain.cbData := Length(Bytes);
  if Length(Bytes) > 0 then
    Plain.pbData := @Bytes[0]
  else
    Plain.pbData := nil;
  Entropy.cbData := Length(cEntropy);
  Entropy.pbData := PByte(PAnsiChar(cEntropy));
  if not CryptProtectData(@Plain, nil, @Entropy, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @Sealed) then
    Exit;
  try
    SetLength(Out_, Sealed.cbData);
    Move(Sealed.pbData^, Out_[0], Sealed.cbData);
  finally
    LocalFree(HLOCAL(Sealed.pbData));
  end;
  Enc := TBase64Encoding.Create(0);
  try
    Result := cPrefix + Enc.EncodeBytesToString(Out_);
  finally
    Enc.Free;
  end;
end;
{$ELSE}
begin
  Result := '';
end;
{$ENDIF}

function UnprotectSecret(const ASealed: string; out AText: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Sealed, Entropy, Plain: TDataBlob;
  Bytes, Out_: TBytes;
begin
  Result := False;
  AText := '';
  if Copy(ASealed, 1, Length(cPrefix)) <> cPrefix then
    Exit;
  try
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(Copy(ASealed, Length(cPrefix) + 1, MaxInt));
  except
    Exit;
  end;
  if Length(Bytes) = 0 then
    Exit;
  Sealed.cbData := Length(Bytes);
  Sealed.pbData := @Bytes[0];
  Entropy.cbData := Length(cEntropy);
  Entropy.pbData := PByte(PAnsiChar(cEntropy));
  if not CryptUnprotectData(@Sealed, nil, @Entropy, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @Plain) then
    Exit;
  try
    SetLength(Out_, Plain.cbData);
    if Plain.cbData > 0 then
      Move(Plain.pbData^, Out_[0], Plain.cbData);
  finally
    LocalFree(HLOCAL(Plain.pbData));
  end;
  AText := TEncoding.UTF8.GetString(Out_);
  Result := True;
end;
{$ELSE}
begin
  AText := '';
  Result := False;
end;
{$ENDIF}

end.
