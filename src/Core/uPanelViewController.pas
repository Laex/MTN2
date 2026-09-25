unit uPanelViewController;

{ Panel View Controller: manages a single side (Left/Right) file panel state,
  model instance, directory watcher, navigation history, and totals calculations. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVfsTypes, uDualPanelTypes, uPanelModel, uDirWatch;

type
  TPanelPlainTotals = record
    Valid: Boolean;
    Bytes: Int64;
    Files: Integer;
    Folders: Integer;
  end;

  TPanelViewController = class
  private
    FSide: TPanelSide;
    FModel: IPanelModel;
    FDirWatch: TDirectoryWatcher;
    FWatchPending: Boolean;
    FPlainTotals: TPanelPlainTotals;
    FOnInvalidate: TNotifyEvent;
  public
    constructor Create(ASide: TPanelSide);
    destructor Destroy; override;

    procedure SetModel(const AModel: IPanelModel);
    procedure InvalidateTotals;
    procedure RecalculateTotalsIfNeeded; overload;
    procedure RecalculateTotalsIfNeeded(const ARows: TPanelRows); overload;
    procedure SetDirWatchPath(const APath: string);
    procedure StopDirWatch;

    property Side: TPanelSide read FSide;
    property Model: IPanelModel read FModel;
    property DirWatch: TDirectoryWatcher read FDirWatch;
    property WatchPending: Boolean read FWatchPending write FWatchPending;
    property PlainTotals: TPanelPlainTotals read FPlainTotals;
    property OnInvalidate: TNotifyEvent read FOnInvalidate write FOnInvalidate;
  end;

implementation

{ TPanelViewController }

constructor TPanelViewController.Create(ASide: TPanelSide);
begin
  inherited Create;
  FSide := ASide;
  FModel := nil;
  FDirWatch := nil;
  FWatchPending := False;
  FPlainTotals.Valid := False;
  FPlainTotals.Bytes := 0;
  FPlainTotals.Files := 0;
  FPlainTotals.Folders := 0;
end;

destructor TPanelViewController.Destroy;
begin
  StopDirWatch;
  FModel := nil;
  inherited Destroy;
end;

procedure TPanelViewController.SetModel(const AModel: IPanelModel);
begin
  FModel := AModel;
  InvalidateTotals;
end;

procedure TPanelViewController.InvalidateTotals;
begin
  FPlainTotals.Valid := False;
  FPlainTotals.Bytes := 0;
  FPlainTotals.Files := 0;
  FPlainTotals.Folders := 0;
end;

procedure TPanelViewController.RecalculateTotalsIfNeeded;
var
  Rows: TPanelRows;
  I, N: Integer;
begin
  if FPlainTotals.Valid then
    Exit;
  if not Assigned(FModel) then
    Exit;
  N := FModel.ItemCount;
  SetLength(Rows, N);
  for I := 0 to N - 1 do
    Rows[I] := FModel.GetRow(I);
  RecalculateTotalsIfNeeded(Rows);
end;

procedure TPanelViewController.RecalculateTotalsIfNeeded(const ARows: TPanelRows);
var
  I: Integer;
begin
  if FPlainTotals.Valid then
    Exit;

  FPlainTotals.Bytes := 0;
  FPlainTotals.Files := 0;
  FPlainTotals.Folders := 0;

  for I := 0 to High(ARows) do
  begin
    if ARows[I].IsParent then
      Continue;
    if ARows[I].IsDirectory then
      Inc(FPlainTotals.Folders)
    else
    begin
      Inc(FPlainTotals.Files);
      if ARows[I].Size > 0 then
        Inc(FPlainTotals.Bytes, ARows[I].Size);
    end;
  end;
  FPlainTotals.Valid := True;
end;

procedure TPanelViewController.SetDirWatchPath(const APath: string);
begin
  StopDirWatch;
  if (APath <> '') and System.SysUtils.DirectoryExists(APath) then
  begin
    try
      FDirWatch := TDirectoryWatcher.Create;
      FDirWatch.SetPath(APath);
    except
      FreeAndNil(FDirWatch);
    end;
  end;
end;

procedure TPanelViewController.StopDirWatch;
begin
  if Assigned(FDirWatch) then
  begin
    FDirWatch.Free;
    FDirWatch := nil;
  end;
  FWatchPending := False;
end;

end.
