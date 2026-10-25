unit uListExport;

{ Saving the marked panel items as a text list: which fields go into the file
  (name, full path, extension, size, dates, type, attributes) and in which
  layout (aligned text, Markdown table, CSV). Pure formatting - the panel
  window collects the items and writes the file. }

interface

uses
  System.SysUtils,
  uDualPanelTypes;

type
  /// <summary>lefAuto picks the layout from the file extension: .md and
  /// .markdown -> Markdown, .csv -> CSV, anything else -> aligned text.</summary>
  TListExportFormat = (lefAuto, lefText, lefMarkdown, lefCsv);

  TListExportField = (lxfName, lxfPath, lxfExt, lxfSize, lxfModified,
    lxfCreated, lxfAccessed, lxfType, lxfAttr);
  TListExportFields = set of TListExportField;

  TListExportConfig = record
    Format: TListExportFormat;
    /// <summary>Column titles as the first line of the text and CSV layouts;
    /// a Markdown table always has them.</summary>
    Header: Boolean;
    Fields: TListExportFields;
  end;

  TListExportItem = record
    /// <summary>Last segment of the path ("" for a drive root).</summary>
    Name: string;
    FullPath: string;
    Row: TPanelRow;
  end;

function DefaultListExportConfig: TListExportConfig;

/// <summary>The layout the file name selects when the config says lefAuto;
/// an explicit config format is returned as it is.</summary>
function ResolveListExportFormat(AFormat: TListExportFormat;
  const AFileName: string): TListExportFormat;

/// <summary>The whole file text, one line per item in the given order. Fields
/// come out in TListExportField order whatever the set's order; an empty
/// field set yields ''.</summary>
function FormatItemList(const AItems: TArray<TListExportItem>;
  const AConfig: TListExportConfig; const AFileName: string): string;

/// <summary>Whether the file should start with a UTF-8 byte order mark:
/// spreadsheets take a CSV as UTF-8 only with it, other layouts stay plain.</summary>
function ListExportNeedsBom(AFormat: TListExportFormat;
  const AFileName: string): Boolean;

var
  /// <summary>App-wide export settings, loaded from and saved to the session.</summary>
  GListExportConfig: TListExportConfig;

implementation

uses
  uStrings;

const
  cAllFields: array[0..8] of TListExportField = (lxfName, lxfPath, lxfExt,
    lxfSize, lxfModified, lxfCreated, lxfAccessed, lxfType, lxfAttr);
  cDirSize = '<DIR>';

function DefaultListExportConfig: TListExportConfig;
begin
  Result.Format := lefAuto;
  Result.Header := True;
  Result.Fields := [lxfName, lxfSize, lxfModified];
end;

function ResolveListExportFormat(AFormat: TListExportFormat;
  const AFileName: string): TListExportFormat;
var
  Ext: string;
begin
  if AFormat <> lefAuto then
    Exit(AFormat);
  Ext := LowerCase(ExtractFileExt(AFileName));
  if (Ext = '.md') or (Ext = '.markdown') then
    Result := lefMarkdown
  else if Ext = '.csv' then
    Result := lefCsv
  else
    Result := lefText;
end;

function ListExportNeedsBom(AFormat: TListExportFormat;
  const AFileName: string): Boolean;
begin
  Result := ResolveListExportFormat(AFormat, AFileName) = lefCsv;
end;

function FieldTitle(AField: TListExportField): string;
begin
  case AField of
    lxfName:     Result := T('col.name', 'Name');
    lxfPath:     Result := T('col.path', 'Path');
    lxfExt:      Result := T('col.ext', 'Ext');
    lxfSize:     Result := T('col.size', 'Size');
    lxfModified: Result := T('col.modified', 'Modified');
    lxfCreated:  Result := T('col.created', 'Created');
    lxfAccessed: Result := T('col.accessed', 'Accessed');
    lxfType:     Result := T('col.type', 'Type');
  else
    Result := T('col.attr', 'Attr');
  end;
end;

function DateCell(AValue: TDateTime): string;
begin
  if AValue <= 0 then
    Exit('');
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', AValue, TFormatSettings.Invariant);
end;

function FieldValue(const AItem: TListExportItem; AField: TListExportField): string;
begin
  case AField of
    lxfName: Result := AItem.Name;
    lxfPath: Result := AItem.FullPath;
    lxfExt:
      Result := AItem.Row.Extension.TrimLeft(['.']);
    lxfSize:
      if AItem.Row.IsDirectory then
        Result := cDirSize
      else
        Result := IntToStr(AItem.Row.Size);
    lxfModified: Result := DateCell(AItem.Row.ModificationTime);
    lxfCreated:  Result := DateCell(AItem.Row.CreationTime);
    lxfAccessed: Result := DateCell(AItem.Row.AccessTime);
    lxfType:     Result := AItem.Row.FileType;
  else
    Result := AItem.Row.AttrText;
  end;
end;

function CsvCell(const AValue: string): string;
begin
  Result := AValue;
  if Result.IndexOfAny([',', '"', #13, #10]) >= 0 then
    Result := '"' + StringReplace(Result, '"', '""', [rfReplaceAll]) + '"';
end;

function MarkdownCell(const AValue: string): string;
begin
  Result := StringReplace(AValue, '|', '\|', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

function PadRight(const AValue: string; AWidth: Integer): string;
begin
  Result := AValue + StringOfChar(' ', AWidth - Length(AValue));
end;

function PadLeft(const AValue: string; AWidth: Integer): string;
begin
  Result := StringOfChar(' ', AWidth - Length(AValue)) + AValue;
end;

function FormatItemList(const AItems: TArray<TListExportItem>;
  const AConfig: TListExportConfig; const AFileName: string): string;
var
  Fields: TArray<TListExportField>;
  Cells: TArray<TArray<string>>;
  Titles: TArray<string>;
  Widths: TArray<Integer>;
  Layout: TListExportFormat;
  Lines: TStringBuilder;
  F: TListExportField;
  I, C: Integer;
  Line: string;

  function JoinCells(const ACells: TArray<string>; const ASep: string;
    AForCsv: Boolean): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to High(ACells) do
    begin
      if K > 0 then
        Result := Result + ASep;
      if AForCsv then
        Result := Result + CsvCell(ACells[K])
      else
        Result := Result + MarkdownCell(ACells[K]);
    end;
  end;

  function TextLine(const ACells: TArray<string>): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to High(ACells) do
    begin
      if Fields[K] = lxfSize then
        Result := Result + PadLeft(ACells[K], Widths[K])
      else
        Result := Result + PadRight(ACells[K], Widths[K]);
      if K < High(ACells) then
        Result := Result + '  ';
    end;
    Result := Result.TrimRight;
  end;

begin
  SetLength(Fields, 0);
  for F in cAllFields do
    if F in AConfig.Fields then
      Fields := Fields + [F];
  if (Length(Fields) = 0) or (Length(AItems) = 0) then
    Exit('');

  SetLength(Titles, Length(Fields));
  for C := 0 to High(Fields) do
    Titles[C] := FieldTitle(Fields[C]);
  SetLength(Cells, Length(AItems));
  for I := 0 to High(AItems) do
  begin
    SetLength(Cells[I], Length(Fields));
    for C := 0 to High(Fields) do
      Cells[I][C] := FieldValue(AItems[I], Fields[C]);
  end;

  Layout := ResolveListExportFormat(AConfig.Format, AFileName);
  Lines := TStringBuilder.Create;
  try
    case Layout of
      lefCsv:
        begin
          if AConfig.Header then
            Lines.Append(JoinCells(Titles, ',', True)).Append(sLineBreak);
          for I := 0 to High(Cells) do
            Lines.Append(JoinCells(Cells[I], ',', True)).Append(sLineBreak);
        end;
      lefMarkdown:
        begin
          Lines.Append('| ').Append(JoinCells(Titles, ' | ', False))
            .Append(' |').Append(sLineBreak);
          Line := '|';
          for C := 0 to High(Fields) do
            if Fields[C] = lxfSize then
              Line := Line + ' ---: |'
            else
              Line := Line + ' --- |';
          Lines.Append(Line).Append(sLineBreak);
          for I := 0 to High(Cells) do
            Lines.Append('| ').Append(JoinCells(Cells[I], ' | ', False))
              .Append(' |').Append(sLineBreak);
        end;
    else
      SetLength(Widths, Length(Fields));
      for C := 0 to High(Fields) do
      begin
        if AConfig.Header then
          Widths[C] := Length(Titles[C])
        else
          Widths[C] := 0;
        for I := 0 to High(Cells) do
          if Length(Cells[I][C]) > Widths[C] then
            Widths[C] := Length(Cells[I][C]);
      end;
      if AConfig.Header then
        Lines.Append(TextLine(Titles)).Append(sLineBreak);
      for I := 0 to High(Cells) do
        Lines.Append(TextLine(Cells[I])).Append(sLineBreak);
    end;
    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

initialization
  GListExportConfig := DefaultListExportConfig;

end.
