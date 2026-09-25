unit uDualPanelFolderSize;

{ Manager for async folder-size calculations in Dual Panel (F3-on-directory).
  Extracted from TDualPanelWindow as part of Step 1 refactoring. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uVfsTypes, uDualPanelTypes, uFolderSize;

type
  TFolderSizeProgressEvent = reference to procedure(ASide: TPanelSide;
    ACompleted, APending: Integer; AFolderBytes: Int64; const AFolderURI: string);

  TFolderSizeCalculationManager = class
  private
    FCancelToken: IJobCancelToken;
    FGen: Cardinal;
    FURI: string;
    FSide: TPanelSide;
    FQueue: TArray<string>;
    FPending: Integer;
    FCompleted: Integer;
    FSumBytes: Int64;
    FOnProgress: TFolderSizeProgressEvent;
    FOnInvalidate: TProc;
    function GetIsActive: Boolean;
  public
    constructor Create(const AOnProgress: TFolderSizeProgressEvent;
      const AOnInvalidate: TProc);
    destructor Destroy; override;

    procedure Cancel;
    procedure Reset;
    procedure StartCalculation(ASide: TPanelSide; const AURI: string;
      const AQueue: TArray<string>);

    property IsActive: Boolean read GetIsActive;
    property PendingCount: Integer read FPending;
    property CompletedCount: Integer read FCompleted;
    property SumBytes: Int64 read FSumBytes;
    property Side: TPanelSide read FSide;
    property URI: string read FURI;
  end;

implementation

constructor TFolderSizeCalculationManager.Create(
  const AOnProgress: TFolderSizeProgressEvent; const AOnInvalidate: TProc);
begin
  inherited Create;
  FOnProgress := AOnProgress;
  FOnInvalidate := AOnInvalidate;
  Reset;
end;

destructor TFolderSizeCalculationManager.Destroy;
begin
  Cancel;
  inherited Destroy;
end;

function TFolderSizeCalculationManager.GetIsActive: Boolean;
begin
  Result := FPending > 0;
end;

procedure TFolderSizeCalculationManager.Cancel;
begin
  if Assigned(FCancelToken) then
  begin
    FCancelToken.Cancel;
    FCancelToken := nil;
  end;
  Inc(FGen);
  FPending := 0;
  SetLength(FQueue, 0);
end;

procedure TFolderSizeCalculationManager.Reset;
begin
  Cancel;
  FURI := '';
  FSide := psLeft;
  FPending := 0;
  FCompleted := 0;
  FSumBytes := 0;
end;

procedure TFolderSizeCalculationManager.StartCalculation(ASide: TPanelSide;
  const AURI: string; const AQueue: TArray<string>);
var
  CapGen: Cardinal;
  CapSide: TPanelSide;
  I: Integer;

  procedure EnqueueOne(const AFolderURI: string);
  var
    CapURI: string;
  begin
    CapURI := AFolderURI;
    CalculateFolderSizeAsync(CapURI, FCancelToken,
      procedure(ABytes: Int64; AFiles, AFolders: Integer; const ACurrentDir: string)
      begin
      end,
      procedure(ABytes: Int64; AFiles, AFolders: Integer; const AError: TVfsError)
      var
        DoneURI: string;
        DoneBytes: Int64;
        DoneOk: Boolean;
      begin
        DoneURI := CapURI;
        DoneBytes := ABytes;
        DoneOk := AError.Code = vecOk;
        TThread.Queue(nil,
          procedure
          begin
            if FGen <> CapGen then
              Exit;
            if DoneOk then
              Inc(FSumBytes, DoneBytes)
            else
              DoneBytes := -1;
            Inc(FCompleted);
            Dec(FPending);
            if Assigned(FOnProgress) then
              FOnProgress(CapSide, FCompleted, FPending, DoneBytes, DoneURI);
            if Assigned(FOnInvalidate) then
              FOnInvalidate;
          end);
      end);
  end;

begin
  Cancel;
  Inc(FGen);
  CapGen := FGen;
  FSide := ASide;
  CapSide := ASide;
  FURI := AURI;
  FQueue := AQueue;
  FPending := Length(AQueue);
  FCompleted := 0;
  FSumBytes := 0;

  if FPending = 0 then
  begin
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    Exit;
  end;

  FCancelToken := TJobCancelToken.Create;

  for I := 0 to High(AQueue) do
    EnqueueOne(AQueue[I]);
end;

end.
