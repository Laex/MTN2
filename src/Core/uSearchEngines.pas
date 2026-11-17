unit uSearchEngines;

{ The lists of the pipeline dialog of the Find dialog (Alt+F7), one per stage: item 0 lets
  the program pick the best provider, item 1 is the built-in code, the rest are the plugins
  that offer the search.files service with the capability of the stage. The state of a
  search keeps each choice as UsePlugins and an engine id; this unit converts between that
  pair and the list index. The host supplies the list
  of providers (SetSearchEngineLister), so this unit knows nothing about plugins. }

interface

type
  TSearchEngine = record
    /// <summary>Plugin id.</summary>
    Id: string;
    /// <summary>Name shown in the list.</summary>
    Title: string;
    /// <summary>The provider lists files by name (capability "list"): it can run the
    /// first stage of the pipeline.</summary>
    CanList: Boolean;
    /// <summary>The provider looks for text in a given list of files (capability
    /// "files"): it can run the second stage.</summary>
    CanFiles: Boolean;
  end;

  TSearchStage = (ssNames, ssText);

  TSearchEngineLister = reference to function: TArray<TSearchEngine>;

const
  cEngineIdxAuto = 0;
  cEngineIdxBuiltIn = 1;
  cEngineIdxFirstPlugin = 2;

procedure SetSearchEngineLister(ALister: TSearchEngineLister);

/// <summary>The providers known to the host; empty without a lister.</summary>
function SearchEngines: TArray<TSearchEngine>;

/// <summary>The providers that can run a stage of the pipeline.</summary>
function SearchStageEngines(const AEngines: TArray<TSearchEngine>;
  AStage: TSearchStage): TArray<TSearchEngine>;

/// <summary>The caption of the pipeline button: "Pipeline: Auto" while both stages are
/// automatic, the two choices otherwise.</summary>
function SearchPipelineCaption(const APipeline, AAuto: string;
  const ANames, AText: TArray<string>; ANamesIdx, ATextIdx: Integer): string;

/// <summary>The list items: Auto, Built-in, then one item per engine.</summary>
function SearchEngineItems(const AEngines: TArray<TSearchEngine>;
  const AAutoText, ABuiltInText: string): TArray<string>;

/// <summary>The list index of a choice; an engine that is not listed gives Auto.</summary>
function SearchEngineIndex(AUsePlugins: Boolean; const AEngine: string;
  const AEngines: TArray<TSearchEngine>): Integer;

/// <summary>The choice of a list index; an index out of range gives Auto.</summary>
procedure SearchEngineFromIndex(AIndex: Integer; const AEngines: TArray<TSearchEngine>;
  out AUsePlugins: Boolean; out AEngine: string);

implementation

uses
  System.SysUtils;

var
  GLister: TSearchEngineLister;

procedure SetSearchEngineLister(ALister: TSearchEngineLister);
begin
  GLister := ALister;
end;

function SearchEngines: TArray<TSearchEngine>;
begin
  if Assigned(GLister) then
    Result := GLister()
  else
    SetLength(Result, 0);
end;

function SearchStageEngines(const AEngines: TArray<TSearchEngine>;
  AStage: TSearchStage): TArray<TSearchEngine>;
var
  I, N: Integer;
begin
  SetLength(Result, Length(AEngines));
  N := 0;
  for I := 0 to High(AEngines) do
    if ((AStage = ssNames) and AEngines[I].CanList) or
       ((AStage = ssText) and AEngines[I].CanFiles) then
    begin
      Result[N] := AEngines[I];
      Inc(N);
    end;
  SetLength(Result, N);
end;

function SearchPipelineCaption(const APipeline, AAuto: string;
  const ANames, AText: TArray<string>; ANamesIdx, ATextIdx: Integer): string;
const
  cMaxCaption = 24;
var
  Detail: string;
begin
  if (ANamesIdx = cEngineIdxAuto) and (ATextIdx = cEngineIdxAuto) then
    Exit(APipeline + ': ' + AAuto);
  Detail := '';
  if (ANamesIdx >= 0) and (ANamesIdx <= High(ANames)) and
     (ATextIdx >= 0) and (ATextIdx <= High(AText)) then
    Detail := ANames[ANamesIdx] + ' > ' + AText[ATextIdx];
  Result := APipeline + ': ' + Detail;
  if (Detail = '') or (Length(Result) > cMaxCaption) then
    Result := APipeline + '...';
end;

function SearchEngineItems(const AEngines: TArray<TSearchEngine>;
  const AAutoText, ABuiltInText: string): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, cEngineIdxFirstPlugin + Length(AEngines));
  Result[cEngineIdxAuto] := AAutoText;
  Result[cEngineIdxBuiltIn] := ABuiltInText;
  for I := 0 to High(AEngines) do
    if AEngines[I].Title <> '' then
      Result[cEngineIdxFirstPlugin + I] := AEngines[I].Title
    else
      Result[cEngineIdxFirstPlugin + I] := AEngines[I].Id;
end;

function SearchEngineIndex(AUsePlugins: Boolean; const AEngine: string;
  const AEngines: TArray<TSearchEngine>): Integer;
var
  I: Integer;
begin
  if not AUsePlugins then
    Exit(cEngineIdxBuiltIn);
  if AEngine <> '' then
    for I := 0 to High(AEngines) do
      if SameText(AEngines[I].Id, AEngine) then
        Exit(cEngineIdxFirstPlugin + I);
  Result := cEngineIdxAuto;
end;

procedure SearchEngineFromIndex(AIndex: Integer; const AEngines: TArray<TSearchEngine>;
  out AUsePlugins: Boolean; out AEngine: string);
begin
  AUsePlugins := True;
  AEngine := '';
  if AIndex = cEngineIdxBuiltIn then
    AUsePlugins := False
  else if (AIndex >= cEngineIdxFirstPlugin) and
          (AIndex - cEngineIdxFirstPlugin <= High(AEngines)) then
    AEngine := AEngines[AIndex - cEngineIdxFirstPlugin].Id;
end;

end.
