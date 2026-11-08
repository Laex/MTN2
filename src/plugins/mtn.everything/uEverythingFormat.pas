unit uEverythingFormat;

{ Pure helpers of the Everything plugin: the address of a search, and the reader of the
  result list that Everything sends back (EVERYTHING_IPC_LISTW).

    everything:///<query>      the files and folders that match the query

  The query is written as one path segment: "/" is %2F, "%" is %25. }

interface

type
  TEvItem = record
    /// <summary>The folder that holds the item.</summary>
    Dir: string;
    Name: string;
    IsDir: Boolean;
  end;
  TEvItems = TArray<TEvItem>;

function EvEncode(const AText: string): string;
function EvDecode(const AText: string): string;
function EverythingUri(const AQuery: string): string;
/// <summary>The query of an everything:/// address; False when it is another address.</summary>
function ParseEverythingUri(const AUri: string; out AQuery: string): Boolean;

/// <summary>The full path of an item.</summary>
function ItemPath(const AItem: TEvItem): string;

/// <summary>Reads the list Everything puts in the data of its WM_COPYDATA answer.
/// False when the block is too short or an offset points outside it.</summary>
function ParseIpcList(AData: Pointer; ASize: Integer; out AItems: TEvItems): Boolean;

/// <summary>The bytes of a query message (EVERYTHING_IPC_QUERYW): the reply window, the
/// message number it is answered with, the flags, the first result, the number of results
/// and the zero-terminated text.</summary>
function BuildIpcQuery(AReplyWnd: Cardinal; AReplyMessage: Cardinal; AMaxResults: Cardinal;
  const AQuery: string): TArray<Byte>;

implementation

uses
  System.SysUtils;

type
  TIpcListHeader = packed record
    TotFolders, TotFiles, TotItems: Cardinal;
    NumFolders, NumFiles, NumItems: Cardinal;
    Offset: Cardinal;
  end;
  PIpcListHeader = ^TIpcListHeader;

  TIpcItem = packed record
    Flags, FilenameOffset, PathOffset: Cardinal;
  end;
  PIpcItem = ^TIpcItem;

  TIpcQueryHeader = packed record
    ReplyWnd, ReplyMessage, SearchFlags, Offset, MaxResults: Cardinal;
  end;

const
  cFolderFlag = 1;

function EvEncode(const AText: string): string;
begin
  Result := AText.Replace('%', '%25').Replace('/', '%2F');
end;

function EvDecode(const AText: string): string;
var
  I: Integer;
  Code: string;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    Code := Copy(AText, I, 3);
    if (AText[I] = '%') and SameText(Code, '%2F') then
    begin
      Result := Result + '/';
      Inc(I, 3);
    end
    else if (AText[I] = '%') and (Code = '%25') then
    begin
      Result := Result + '%';
      Inc(I, 3);
    end
    else
    begin
      Result := Result + AText[I];
      Inc(I);
    end;
  end;
end;

function EverythingUri(const AQuery: string): string;
begin
  Result := 'everything:///' + EvEncode(AQuery);
end;

function ParseEverythingUri(const AUri: string; out AQuery: string): Boolean;
const
  cPrefix = 'everything:///';
begin
  AQuery := '';
  Result := SameText(Copy(AUri, 1, Length(cPrefix)), cPrefix);
  if Result then
    AQuery := EvDecode(Copy(AUri, Length(cPrefix) + 1, MaxInt));
end;

function ItemPath(const AItem: TEvItem): string;
begin
  if AItem.Dir = '' then
    Exit(AItem.Name);
  if AItem.Dir[Length(AItem.Dir)] = '\' then
    Result := AItem.Dir + AItem.Name
  else
    Result := AItem.Dir + '\' + AItem.Name;
end;

// A zero-terminated UTF-16 string at AOffset of the block; False when it does not end inside.
function ReadWide(AData: Pointer; ASize: Integer; AOffset: Cardinal; out AText: string): Boolean;
var
  P: PWideChar;
  Limit: Integer;
  N: Integer;
begin
  AText := '';
  Result := False;
  if (AOffset >= Cardinal(ASize)) or (AOffset mod 2 <> 0) then
    Exit;
  P := PWideChar(PByte(AData) + AOffset);
  Limit := (ASize - Integer(AOffset)) div 2;
  N := 0;
  while (N < Limit) and (P[N] <> #0) do
    Inc(N);
  if N >= Limit then
    Exit;
  SetString(AText, P, N);
  Result := True;
end;

function ParseIpcList(AData: Pointer; ASize: Integer; out AItems: TEvItems): Boolean;
var
  Head: PIpcListHeader;
  Item: PIpcItem;
  I, N: Integer;
  E: TEvItem;
begin
  SetLength(AItems, 0);
  Result := False;
  if (AData = nil) or (ASize < SizeOf(TIpcListHeader)) then
    Exit;
  Head := PIpcListHeader(AData);
  if Int64(Head.NumItems) * SizeOf(TIpcItem) + SizeOf(TIpcListHeader) > ASize then
    Exit;
  N := Integer(Head.NumItems);
  SetLength(AItems, N);
  for I := 0 to N - 1 do
  begin
    Item := PIpcItem(PByte(AData) + SizeOf(TIpcListHeader) + I * SizeOf(TIpcItem));
    E := Default(TEvItem);
    E.IsDir := (Item.Flags and cFolderFlag) <> 0;
    if not ReadWide(AData, ASize, Item.FilenameOffset, E.Name) or
       not ReadWide(AData, ASize, Item.PathOffset, E.Dir) then
    begin
      SetLength(AItems, 0);
      Exit;
    end;
    AItems[I] := E;
  end;
  Result := True;
end;

function BuildIpcQuery(AReplyWnd: Cardinal; AReplyMessage: Cardinal; AMaxResults: Cardinal;
  const AQuery: string): TArray<Byte>;
var
  Head: TIpcQueryHeader;
begin
  Head := Default(TIpcQueryHeader);
  Head.ReplyWnd := AReplyWnd;
  Head.ReplyMessage := AReplyMessage;
  Head.MaxResults := AMaxResults;
  SetLength(Result, SizeOf(Head) + (Length(AQuery) + 1) * SizeOf(WideChar));
  Move(Head, Result[0], SizeOf(Head));
  if Length(AQuery) > 0 then
    Move(PWideChar(AQuery)^, Result[SizeOf(Head)], Length(AQuery) * SizeOf(WideChar));
  // The terminator is the last character; SetLength does not clear a reused block.
  Result[High(Result)] := 0;
  Result[High(Result) - 1] := 0;
end;

end.
