unit uFileAttrTypes;

{ Data shared by the Set attributes dialog and the platform code that reads and
  writes the attributes of a local file. }

interface

type
  TFileAttrChoice = (facKeep, facSet, facClear);

  /// <summary>Local times; 0 = unknown (or, in the dialog state, differs
  /// between the selected items).</summary>
  TFileAttrTimes = record
    Created: TDateTime;
    Modified: TDateTime;
    Accessed: TDateTime;
  end;

  TFileAttrSnapshot = record
    ReadOnly: Boolean;
    Hidden: Boolean;
    System: Boolean;
    Archive: Boolean;
    // Windows only: the other attribute flags of the file.
    Compressed: Boolean;
    Encrypted: Boolean;
    NotIndexed: Boolean;
    Sparse: Boolean;
    Temporary: Boolean;
    Offline: Boolean;
    // POSIX only: the file system flags chattr sets (immutable, append only, no dump).
    Immutable: Boolean;
    AppendOnly: Boolean;
    NoDump: Boolean;
    Owner: string;
    // Permission bits (0..$FFF) and the group name; Mode = -1 where the
    // platform has no permission bits.
    Mode: Integer;
    Group: string;
    Times: TFileAttrTimes;
  end;

  TFileAttrPlan = record
    ReadOnly: TFileAttrChoice;
    Hidden: TFileAttrChoice;
    System: TFileAttrChoice;
    Archive: TFileAttrChoice;
    Compressed: TFileAttrChoice;
    Encrypted: TFileAttrChoice;
    NotIndexed: TFileAttrChoice;
    Sparse: TFileAttrChoice;
    Temporary: TFileAttrChoice;
    Offline: TFileAttrChoice;
    Immutable: TFileAttrChoice;
    AppendOnly: TFileAttrChoice;
    NoDump: TFileAttrChoice;
    ChangeOwner: Boolean;
    Owner: string;
    // An empty Group keeps the group while the owner changes.
    ChangeGroup: Boolean;
    Group: string;
    ChangeMode: Boolean;
    Mode: Integer;
    Recurse: Boolean;
    // Only the flagged times are written; the rest keep their value.
    SetCreated: Boolean;
    SetModified: Boolean;
    SetAccessed: Boolean;
    Times: TFileAttrTimes;
  end;

  TFileAttrDialogState = record
    Summary: string;
    Owner: string;
    OwnerMixed: Boolean;
    ReadOnly: TFileAttrChoice;
    Hidden: TFileAttrChoice;
    System: TFileAttrChoice;
    Archive: TFileAttrChoice;
    Compressed: TFileAttrChoice;
    Encrypted: TFileAttrChoice;
    NotIndexed: TFileAttrChoice;
    Sparse: TFileAttrChoice;
    Temporary: TFileAttrChoice;
    Offline: TFileAttrChoice;
    Immutable: TFileAttrChoice;
    AppendOnly: TFileAttrChoice;
    NoDump: TFileAttrChoice;
    // Volume GUID path and device of a drive root ('' for any other item).
    Volume: string;
    Device: string;
    // Mode and Group of the first readable item; -1 when none is readable.
    Mode: Integer;
    Group: string;
    Times: TFileAttrTimes;
  end;

/// <summary>Permission bits as four octal digits, e.g. 0644.</summary>
function FileModeToOctal(AMode: Integer): string;
/// <summary>Permission bits as ls shows them, e.g. rw-r--r--.</summary>
function FileModeToSymbolic(AMode: Integer): string;
/// <summary>Parses 1 to 4 octal digits; False for anything else.</summary>
function TryParseFileMode(const AText: string; out AMode: Integer): Boolean;

implementation

function FileModeToSymbolic(AMode: Integer): string;
const
  cBits = 'rwxrwxrwx';
var
  I: Integer;
begin
  Result := '';
  for I := 0 to 8 do
    if (AMode and (1 shl (8 - I))) <> 0 then
      Result := Result + cBits[I + 1]
    else
      Result := Result + '-';
end;

function TryParseFileMode(const AText: string; out AMode: Integer): Boolean;
var
  I: Integer;
begin
  AMode := 0;
  Result := (Length(AText) >= 1) and (Length(AText) <= 4);
  if not Result then
    Exit;
  for I := 1 to Length(AText) do
  begin
    if (AText[I] < '0') or (AText[I] > '7') then
      Exit(False);
    AMode := AMode * 8 + (Ord(AText[I]) - Ord('0'));
  end;
end;

function FileModeToOctal(AMode: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 3 downto 0 do
    Result := Result + Chr(Ord('0') + ((AMode shr (I * 3)) and 7));
end;

end.
