unit uSearchHitsJson;

{ The provider side of the search.hits message of search.files (docs/PLUGIN_SERVICES.md):
  a found entry with what was read from the file, the message that carries a batch of
  entries, and the read of a file's size, times and attributes. }

interface

type
  /// <summary>A found entry. Size is -1 when unknown; times are local ISO 8601
  /// ('' = unknown); Attributes holds Windows attribute bits (0 = unknown); Line is 0
  /// for a name match.</summary>
  TSearchHit = record
    Path: string;
    IsDir: Boolean;
    Size: Int64;
    Modified, Created, Accessed: string;
    Attributes: Integer;
    Line: Integer;
    Snippet: string;
  end;

/// <summary>A hit for APath with no data but the kind.</summary>
function NewSearchHit(const APath: string; AIsDir: Boolean): TSearchHit;

/// <summary>Local time as ISO 8601 (yyyy-mm-ddThh:nn:ss).</summary>
function IsoLocalTime(ATime: TDateTime): string;

/// <summary>Fills size, times and attributes of AHit from the file named by AHit.Path.
/// False when the file does not exist.</summary>
function ReadHitFileInfo(var AHit: TSearchHit): Boolean;

/// <summary>The search.hits notification for AHits[AFrom .. AFrom + ACount - 1]. Fields
/// that are unknown are left out; a folder carries no size.</summary>
function BuildSearchHitsMessage(const AHits: TArray<TSearchHit>; AFrom, ACount: Integer): string;

implementation

uses
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  System.SysUtils, System.JSON;

function NewSearchHit(const APath: string; AIsDir: Boolean): TSearchHit;
begin
  Result := Default(TSearchHit);
  Result.Path := APath;
  Result.IsDir := AIsDir;
  Result.Size := -1;
end;

function IsoLocalTime(ATime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', ATime);
end;

{$IFDEF MSWINDOWS}
function FileTimeIso(const AFileTime: TFileTime): string;
var
  Local: TFileTime;
  Sys: TSystemTime;
begin
  Result := '';
  if (AFileTime.dwLowDateTime = 0) and (AFileTime.dwHighDateTime = 0) then
    Exit;
  if FileTimeToLocalFileTime(AFileTime, Local) and FileTimeToSystemTime(Local, Sys) then
    Result := IsoLocalTime(SystemTimeToDateTime(Sys));
end;
{$ENDIF}

{$WARN SYMBOL_PLATFORM OFF}
function ReadHitFileInfo(var AHit: TSearchHit): Boolean;
var
  SR: TSearchRec;
begin
  Result := FindFirst(AHit.Path, faAnyFile, SR) = 0;
  if not Result then
    Exit;
  try
    AHit.Size := SR.Size;
    AHit.Modified := IsoLocalTime(SR.TimeStamp);
    {$IFDEF MSWINDOWS}
    AHit.Created := FileTimeIso(SR.FindData.ftCreationTime);
    AHit.Accessed := FileTimeIso(SR.FindData.ftLastAccessTime);
    AHit.Attributes := Integer(SR.Attr);
    {$ENDIF}
  finally
    FindClose(SR);
  end;
end;

function BuildSearchHitsMessage(const AHits: TArray<TSearchHit>; AFrom, ACount: Integer): string;
var
  Msg, Params, Item: TJSONObject;
  List: TJSONArray;
  I: Integer;
begin
  Msg := TJSONObject.Create;
  try
    Msg.AddPair('jsonrpc', '2.0');
    Msg.AddPair('method', 'search.hits');
    Params := TJSONObject.Create;
    Msg.AddPair('params', Params);
    List := TJSONArray.Create;
    Params.AddPair('hits', List);
    for I := AFrom to AFrom + ACount - 1 do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('path', AHits[I].Path);
      Item.AddPair('isDir', TJSONBool.Create(AHits[I].IsDir));
      if (AHits[I].Size >= 0) and not AHits[I].IsDir then
        Item.AddPair('size', TJSONNumber.Create(AHits[I].Size));
      if AHits[I].Modified <> '' then
        Item.AddPair('modified', AHits[I].Modified);
      if AHits[I].Created <> '' then
        Item.AddPair('created', AHits[I].Created);
      if AHits[I].Accessed <> '' then
        Item.AddPair('accessed', AHits[I].Accessed);
      if AHits[I].Attributes <> 0 then
        Item.AddPair('attributes', TJSONNumber.Create(AHits[I].Attributes));
      if AHits[I].Line > 0 then
        Item.AddPair('line', TJSONNumber.Create(AHits[I].Line));
      if AHits[I].Snippet <> '' then
        Item.AddPair('snippet', AHits[I].Snippet);
      List.AddElement(Item);
    end;
    Result := Msg.ToJSON;
  finally
    Msg.Free;
  end;
end;

end.
