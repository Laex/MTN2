unit uFolderDescriptionCache;

{ Descript.ion of the folder under the cursor, for the status line. The file
  is read off the UI thread: on an unreachable network drive the probes block.
  The cached text is shown until a refresh lands, and a refresh is not started
  again while one is already running. }

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TFolderDescriptionCache = class
  private
    FDir: string;
    FStamp: TDateTime;
    FCheckedAt: UInt64;
    FBusy: Boolean;
    FMap: TDictionary<string, string>;
    FAlive: TFunc<Boolean>;
    FOnChanged: TProc;
  public
    constructor Create(const AAlive: TFunc<Boolean>; const AOnChanged: TProc);
    destructor Destroy; override;
    /// <summary>The next lookup reads the file again. The text already shown
    /// stays until that read finishes.</summary>
    procedure Forget;
    function TextOf(const ADirUri, AName: string): string;
  end;

/// <summary>True when a lookup should read Descript.ion. ABusy skips it, so
/// two reads of the same folder do not run at once. The same folder is read
/// again only after 1500 ms.</summary>
function DescriptionCacheDue(ABusy: Boolean; const ADir, AKnownDir: string;
  AHasMap: Boolean; ATick, ACheckedAt: UInt64): Boolean;

implementation

uses
  System.Classes,
  uVfsTypes, uDescriptIon, uPlatformInfo;

function DescriptionCacheDue(ABusy: Boolean; const ADir, AKnownDir: string;
  AHasMap: Boolean; ATick, ACheckedAt: UInt64): Boolean;
begin
  Result := (not ABusy) and
    ((not SameLocalPath(ADir, AKnownDir)) or (not AHasMap) or
     (ATick - ACheckedAt > 1500));
end;

constructor TFolderDescriptionCache.Create(const AAlive: TFunc<Boolean>;
  const AOnChanged: TProc);
begin
  inherited Create;
  FAlive := AAlive;
  FOnChanged := AOnChanged;
end;

destructor TFolderDescriptionCache.Destroy;
begin
  FMap.Free;
  inherited Destroy;
end;

procedure TFolderDescriptionCache.Forget;
begin
  FCheckedAt := 0;
  FStamp := -1;
end;

function TFolderDescriptionCache.TextOf(const ADirUri, AName: string): string;
var
  Dir, KnownDir: string;
  KnownStamp: TDateTime;
  Tick: UInt64;
  Life: TFunc<Boolean>;
  Changed: TProc;
begin
  Result := '';
  Dir := FileUriToPath(ADirUri);
  if (Dir = '') or (AName = '') then
    Exit;
  Tick := PlatformTickCount64;
  if DescriptionCacheDue(FBusy, Dir, FDir, FMap <> nil, Tick, FCheckedAt) then
  begin
    FBusy := True;
    KnownDir := FDir;
    KnownStamp := FStamp;
    if FMap = nil then
      KnownDir := '';
    // Copied before the read. The queued update can run after this object is
    // freed; taking the flag from the object then reads freed memory. The
    // flag is cleared before the object is freed, so a set flag means the
    // fields below are still there.
    Life := FAlive;
    Changed := FOnChanged;
    TThread.CreateAnonymousThread(
      procedure
      var
        Path: string;
        Stamp: TDateTime;
        Loaded: TDictionary<string, string>;
      begin
        Loaded := nil;
        try
          Path := DescriptionsFilePath(Dir);
          if not FileAge(Path, Stamp) then
            Stamp := 0;
          if (not SameLocalPath(Dir, KnownDir)) or (Stamp <> KnownStamp) then
            Loaded := LoadDescriptions(Dir);
        except
          FreeAndNil(Loaded);
          Stamp := 0;
        end;
        TThread.Queue(nil,
          procedure
          begin
            if not Assigned(Life) or not Life() then
            begin
              Loaded.Free;
              Exit;
            end;
            FBusy := False;
            FCheckedAt := PlatformTickCount64;
            if Loaded <> nil then
            begin
              FMap.Free;
              FMap := Loaded;
              FDir := Dir;
              FStamp := Stamp;
              if Assigned(Changed) then
                Changed();
            end;
          end);
      end).Start;
  end;
  if (FMap = nil) or not SameLocalPath(Dir, FDir) or not FMap.TryGetValue(AName, Result) then
    Result := '';
end;

end.
