unit uArchiveTest;

{***************************************************************************}
{ Integrity test of a ZIP archive without unpacking to disk: every entry is  }
{ decompressed into a counting sink and its CRC-32 compared with the one    }
{ recorded in the archive.                                                  }
{***************************************************************************}

interface

uses
  System.SysUtils, System.Classes;

type
  TArchiveTestCancelled = reference to function: Boolean;

  TArchiveTestResult = record
    Checked: Integer;        // file entries read to the end
    Failed: Integer;         // entries with a CRC mismatch or a read error
    Cancelled: Boolean;
    Errors: TArray<string>;  // "name: reason", at most cArchiveTestMaxErrors
  end;

const
  cArchiveTestMaxErrors = 200;

/// <summary>Tests every file entry of the ZIP at APath. A damaged central
/// directory raises; damaged entries are reported in the result.</summary>
function TestZipArchive(const APath: string;
  const ACancelled: TArchiveTestCancelled): TArchiveTestResult;

implementation

uses
  System.Zip, System.ZLib, uZipNames;

procedure AddError(var AResult: TArchiveTestResult; const AName, AReason: string);
begin
  Inc(AResult.Failed);
  if Length(AResult.Errors) < cArchiveTestMaxErrors then
    AResult.Errors := AResult.Errors + [AName + ': ' + AReason];
end;

function TestZipArchive(const APath: string;
  const ACancelled: TArchiveTestCancelled): TArchiveTestResult;
var
  Zip: TZipFile;
  I, Got: Integer;
  Local: TStream;
  LH: TZipHeader;
  Buf: TBytes;
  Crc: Cardinal;
  Name: string;
begin
  Result := Default(TArchiveTestResult);
  SetLength(Buf, 256 * 1024);
  Zip := NewReadZipFile;
  try
    Zip.Open(APath, zmRead);
    for I := 0 to Zip.FileCount - 1 do
    begin
      if Assigned(ACancelled) and ACancelled() then
      begin
        Result.Cancelled := True;
        Exit;
      end;
      Name := Zip.FileName[I];
      if Name.EndsWith('/') or Name.EndsWith('\') then
        Continue;
      try
        Zip.Read(I, Local, LH);
        try
          Crc := crc32(0, nil, 0);
          repeat
            Got := Local.Read(Buf[0], Length(Buf));
            if Got > 0 then
              Crc := crc32(Crc, @Buf[0], Got);
            if Assigned(ACancelled) and ACancelled() then
            begin
              Result.Cancelled := True;
              Exit;
            end;
          until Got <= 0;
        finally
          Local.Free;
        end;
        Inc(Result.Checked);
        if Crc <> Zip.FileInfo[I].CRC32 then
          AddError(Result, Name, 'CRC mismatch');
      except
        on E: Exception do
        begin
          Inc(Result.Checked);
          AddError(Result, Name, E.Message);
        end;
      end;
    end;
  finally
    Zip.Free;
  end;
end;

end.
