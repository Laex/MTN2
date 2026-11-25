unit uDualPanelPluginJson;

{ JSON the plugin host reads from the panels. The window still picks the
  workspace and the rows; a parent row is left out of the list and does not
  count toward the cursor index, and the list stops after 10000 data rows
  (the next one would be a long pause and a huge payload). }

interface

uses
  uDualPanelTypes;

const
  cPluginPanelListMaxRows = 10000;

type
  TPluginPanelSideInfo = record
    Uri: string;
    Rows: TPanelRows;
    CursorIndex: Integer;
    Selected: TArray<string>;
  end;

/// <summary>0 is the left panel, 1 the right, any other number the panel
/// that is active. A plugin passes the number.</summary>
function PluginPanelSide(ASide: Integer; AActive: TPanelSide): TPanelSide;

/// <summary>active/left/right object. A cursor on the parent row or off the
/// list is omitted; selected is always present.</summary>
function BuildPluginPanelInfoJson(AActiveLeft: Boolean;
  const ALeft, ARight: TPluginPanelSideInfo): string;

/// <summary>One panel's rows. The cursor value is an index into the returned
/// rows, so the parent row is not an index.</summary>
function BuildPluginPanelListJson(const AUri: string; const ARows: TPanelRows;
  ACursorIndex: Integer): string;

implementation

uses
  System.SysUtils, System.JSON, uPluginColumns;

function PluginPanelSide(ASide: Integer; AActive: TPanelSide): TPanelSide;
begin
  case ASide of
    0: Result := psLeft;
    1: Result := psRight;
  else
    Result := AActive;
  end;
end;

procedure WritePluginPanelSide(ARoot: TJSONObject; const AName: string;
  const ASide: TPluginPanelSideInfo);
var
  SideObj: TJSONObject;
  Sel: TJSONArray;
  U: string;
  Idx: Integer;
begin
  SideObj := TJSONObject.Create;
  SideObj.AddPair('uri', ASide.Uri);
  Idx := ASide.CursorIndex;
  if (Idx >= 0) and (Idx <= High(ASide.Rows)) and not ASide.Rows[Idx].IsParent then
  begin
    SideObj.AddPair('cursor', ASide.Rows[Idx].URI);
    SideObj.AddPair('cursorIsDirectory', TJSONBool.Create(ASide.Rows[Idx].IsDirectory));
  end;
  Sel := TJSONArray.Create;
  for U in ASide.Selected do
    Sel.Add(U);
  SideObj.AddPair('selected', Sel);
  ARoot.AddPair(AName, SideObj);
end;

function BuildPluginPanelInfoJson(AActiveLeft: Boolean;
  const ALeft, ARight: TPluginPanelSideInfo): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    if AActiveLeft then
      Root.AddPair('active', 'left')
    else
      Root.AddPair('active', 'right');
    WritePluginPanelSide(Root, 'left', ALeft);
    WritePluginPanelSide(Root, 'right', ARight);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function BuildPluginPanelListJson(const AUri: string; const ARows: TPanelRows;
  ACursorIndex: Integer): string;
var
  Root, RowObj, ColsObj: TJSONObject;
  RowsArr: TJSONArray;
  I, N: Integer;
  ColId, ColText, Name: string;
  HasCells: Boolean;
begin
  HasCells := FolderHasCells(AUri);
  Root := TJSONObject.Create;
  try
    Root.AddPair('uri', AUri);
    RowsArr := TJSONArray.Create;
    N := 0;
    for I := 0 to High(ARows) do
    begin
      if ARows[I].IsParent then
        Continue;
      if N >= cPluginPanelListMaxRows then
      begin
        Root.AddPair('truncated', TJSONBool.Create(True));
        Break;
      end;
      RowObj := TJSONObject.Create;
      RowObj.AddPair('uri', ARows[I].URI);
      RowObj.AddPair('name', ARows[I].Text);
      RowObj.AddPair('dir', TJSONBool.Create(ARows[I].IsDirectory));
      RowObj.AddPair('size', TJSONNumber.Create(ARows[I].Size));
      if ARows[I].ModificationTime > 0 then
        RowObj.AddPair('mtime', TJSONNumber.Create(ARows[I].ModificationTime));
      if ARows[I].CreationTime > 0 then
        RowObj.AddPair('ctime', TJSONNumber.Create(ARows[I].CreationTime));
      if ARows[I].AccessTime > 0 then
        RowObj.AddPair('atime', TJSONNumber.Create(ARows[I].AccessTime));
      if ARows[I].FileType <> '' then
        RowObj.AddPair('type', ARows[I].FileType);
      if ARows[I].AttrText <> '' then
        RowObj.AddPair('attr', ARows[I].AttrText);
      if ARows[I].Extension <> '' then
        RowObj.AddPair('ext', ARows[I].Extension);
      ColsObj := nil;
      if HasCells then
      begin
        Name := ARows[I].Text;
        if (Name <> '') and (Name[Length(Name)] = '/') then
          Delete(Name, Length(Name), 1);
        for ColId in ['dim', 'camera', 'artist', 'title'] do
          if FolderCellText(AUri, Name, ColId, ColText) and (ColText <> '') then
          begin
            if ColsObj = nil then
              ColsObj := TJSONObject.Create;
            ColsObj.AddPair(ColId, ColText);
          end;
      end;
      if ColsObj <> nil then
        RowObj.AddPair('cols', ColsObj);
      RowsArr.Add(RowObj);
      if I = ACursorIndex then
        Root.AddPair('cursor', TJSONNumber.Create(N));
      Inc(N);
    end;
    Root.AddPair('rows', RowsArr);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
