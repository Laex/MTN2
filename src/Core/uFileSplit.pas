unit uFileSplit;

{ Split a file into numbered parts (name.001, name.002, ...) and join them
  back. Parts are plain slices, the same layout as the Total Commander and
  HJSplit families, so the files can be joined by "copy /b" too.

  Pure logic -- TDualPanelWindow runs it on a worker thread. }

interface

uses
  System.SysUtils;

type
  /// <summary>True = stop (the user cancelled).</summary>
  TSplitCancelled = reference to function: Boolean;

const
  cSplitMinPartSize = 1024;

/// <summary>"700M", "1.44M", "4G", "64K", "1000000" (K/M/G are powers of
/// 1024, an optional trailing B is ignored; a comma works as the decimal
/// separator). False for empty text, a bad number or less than one byte.</summary>
function ParseSplitSize(const AText: string; out ABytes: Int64): Boolean;

/// <summary>Part file name: AIndex is 1-based, at least three digits.</summary>
function SplitPartName(const ABaseName: string; AIndex: Integer): string;
/// <summary>True when AFileName ends in a numeric extension of three or
/// more digits; ABase is the name without it, AIndex the number.</summary>
function SplitPartInfo(const AFileName: string; out ABase: string;
  out AIndex: Integer): Boolean;
/// <summary>Number of parts ASize bytes make with APartSize-byte parts
/// (an empty file still makes one).</summary>
function SplitPartCount(ASize, APartSize: Int64): Integer;

/// <summary>Writes ASrc as parts into ADestDir. Returns False when
/// cancelled; the parts written so far are removed then, and also when an
/// exception is raised. Raises when the first part already exists.</summary>
function SplitFile(const ASrc, ADestDir: string; APartSize: Int64;
  const ACancelled: TSplitCancelled; out APartCount: Integer): Boolean;

/// <summary>The run of consecutive parts that starts at AAnyPart's number 1
/// (name.001, name.002, ... in the same folder). Empty when AAnyPart is not
/// a part or name.001 is missing.</summary>
function CollectSplitParts(const AAnyPart: string): TArray<string>;
/// <summary>Where a join of AAnyPart's set is written by default: the part
/// name without the number.</summary>
function CombineDefaultName(const AAnyPart: string): string;

/// <summary>Joins AParts, in order, into ADest. The result appears under
/// its name only when complete: written as "ADest.tmp" and renamed.
/// Returns False when cancelled. Raises when ADest already exists or is one
/// of the parts.</summary>
function CombineParts(const AParts: TArray<string>; const ADest: string;
  const ACancelled: TSplitCancelled): Boolean;

implementation

uses
  System.Classes, System.IOUtils, System.Math;

const
  cBlockSize = 1024 * 1024;

function ParseSplitSize(const AText: string; out ABytes: Int64): Boolean;
var
  S: string;
  Mult: Int64;
  Value: Double;
  FS: TFormatSettings;
begin
  ABytes := 0;
  S := Trim(AText).ToUpper.Replace(' ', '').Replace(',', '.');
  if S.EndsWith('B') then
    S := Copy(S, 1, Length(S) - 1);
  Mult := 1;
  if S <> '' then
    case S[Length(S)] of
      'K': Mult := Int64(1024);
      'M': Mult := Int64(1024) * 1024;
      'G': Mult := Int64(1024) * 1024 * 1024;
    end;
  if Mult > 1 then
    S := Copy(S, 1, Length(S) - 1);
  FS := TFormatSettings.Invariant;
  if (S = '') or not TryStrToFloat(S, Value, FS) or (Value <= 0) or
     (Value * Mult > 4.0E15) then
    Exit(False);
  ABytes := Trunc(Value * Mult);
  Result := ABytes >= 1;
end;

function SplitPartName(const ABaseName: string; AIndex: Integer): string;
begin
  Result := ABaseName + '.' + Format('%.3d', [AIndex]);
end;

function SplitPartInfo(const AFileName: string; out ABase: string;
  out AIndex: Integer): Boolean;
var
  Ext, Digits: string;
  I: Integer;
begin
  ABase := '';
  AIndex := 0;
  Ext := TPath.GetExtension(AFileName);
  Digits := Copy(Ext, 2, MaxInt);
  Result := Length(Digits) >= 3;
  for I := 1 to Length(Digits) do
    if (Digits[I] < '0') or (Digits[I] > '9') then
      Result := False;
  Result := Result and (Length(Digits) <= 9) and TryStrToInt(Digits, AIndex) and
    (AIndex >= 1);
  if Result then
    ABase := Copy(AFileName, 1, Length(AFileName) - Length(Ext))
  else
    AIndex := 0;
end;

function SplitPartCount(ASize, APartSize: Int64): Integer;
begin
  if (ASize <= 0) or (APartSize <= 0) then
    Exit(1);
  Result := Integer((ASize + APartSize - 1) div APartSize);
end;

procedure DeleteQuietly(const APaths: TArray<string>);
var
  P: string;
begin
  for P in APaths do
    try
      if TFile.Exists(P) then
        TFile.Delete(P);
    except
    end;
end;

function SplitFile(const ASrc, ADestDir: string; APartSize: Int64;
  const ACancelled: TSplitCancelled; out APartCount: Integer): Boolean;
var
  Src: TFileStream;
  Dst: TFileStream;
  Buf: TBytes;
  Base, PartPath: string;
  Written: TArray<string>;
  Remaining, InPart: Int64;
  N, Idx: Integer;
  Ok: Boolean;
begin
  APartCount := 0;
  if APartSize < 1 then
    raise EArgumentException.Create('Part size must be positive');
  Base := TPath.Combine(ADestDir, TPath.GetFileName(ASrc));
  if TFile.Exists(SplitPartName(Base, 1)) then
    raise EInOutError.Create('Already exists: ' + SplitPartName(Base, 1));
  SetLength(Buf, cBlockSize);
  SetLength(Written, 0);
  Ok := False;
  Src := TFileStream.Create(ASrc, fmOpenRead or fmShareDenyNone);
  try
    try
      Idx := 0;
      Remaining := Src.Size;
      repeat
        Inc(Idx);
        PartPath := SplitPartName(Base, Idx);
        Written := Written + [PartPath];
        Dst := TFileStream.Create(PartPath, fmCreate);
        try
          InPart := Min(APartSize, Remaining);
          Remaining := Remaining - InPart;
          while InPart > 0 do
          begin
            if Assigned(ACancelled) and ACancelled() then
              Exit(False);
            N := Src.Read(Buf[0], Integer(Min(Int64(cBlockSize), InPart)));
            if N <= 0 then
              raise EReadError.Create('Unexpected end of ' + ASrc);
            Dst.WriteBuffer(Buf[0], N);
            Dec(InPart, N);
          end;
        finally
          Dst.Free;
        end;
      until Remaining <= 0;
      APartCount := Idx;
      Ok := True;
      Result := True;
    finally
      if not Ok then
      begin
        APartCount := 0;
        Src.Free;
        Src := nil;
        DeleteQuietly(Written);
      end;
    end;
  finally
    Src.Free;
  end;
end;

function CollectSplitParts(const AAnyPart: string): TArray<string>;
var
  Base, Path: string;
  Idx, I: Integer;
begin
  SetLength(Result, 0);
  if not SplitPartInfo(AAnyPart, Base, Idx) then
    Exit;
  I := 1;
  while True do
  begin
    Path := SplitPartName(Base, I);
    if not TFile.Exists(Path) then
      Break;
    Result := Result + [Path];
    Inc(I);
  end;
end;

function CombineDefaultName(const AAnyPart: string): string;
var
  Idx: Integer;
begin
  if not SplitPartInfo(AAnyPart, Result, Idx) then
    Result := AAnyPart + '.joined';
end;

function CombineParts(const AParts: TArray<string>; const ADest: string;
  const ACancelled: TSplitCancelled): Boolean;
var
  Tmp, P: string;
  Src, Dst: TFileStream;
  Buf: TBytes;
  N: Integer;
  Ok: Boolean;
begin
  if Length(AParts) = 0 then
    raise EArgumentException.Create('No parts');
  if TFile.Exists(ADest) then
    raise EInOutError.Create('Already exists: ' + ADest);
  for P in AParts do
    if SameText(TPath.GetFullPath(P), TPath.GetFullPath(ADest)) then
      raise EInOutError.Create('The result would overwrite a part');
  Tmp := ADest + '.tmp';
  SetLength(Buf, cBlockSize);
  Ok := False;
  Dst := TFileStream.Create(Tmp, fmCreate);
  try
    try
      for P in AParts do
      begin
        Src := TFileStream.Create(P, fmOpenRead or fmShareDenyNone);
        try
          repeat
            if Assigned(ACancelled) and ACancelled() then
              Exit(False);
            N := Src.Read(Buf[0], cBlockSize);
            if N > 0 then
              Dst.WriteBuffer(Buf[0], N);
          until N <= 0;
        finally
          Src.Free;
        end;
      end;
      Ok := True;
    finally
      Dst.Free;
      Dst := nil;
      if not Ok then
        DeleteQuietly([Tmp]);
    end;
  except
    DeleteQuietly([Tmp]);
    raise;
  end;
  TFile.Move(Tmp, ADest);
  Result := True;
end;

end.
