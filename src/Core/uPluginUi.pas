unit uPluginUi;

{ Bridge between plugins and the host's windows: a plugin asks the host to
  show a dialog, described as JSON (the same declaration the built-in dialogs
  use, see DIALOG_PLUGIN.md), and gets the control id and the values of the
  dialog back when the user presses a button. The host window that shows the
  dialog registers itself with SetPluginDialogHost; without one (tests,
  tools) nothing is shown and the call reports failure.

  The dialog is modal and one-shot: any command closes it and is reported
  once. A plugin that wants to keep a dialog going shows the next one from
  its callback.

  A callback never reaches a plugin that has been unloaded in the meantime:
  UnregisterPlugin invalidates the pending callbacks of that plugin. Main
  thread only. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uDialogTypes;

type
  /// <summary>Shows ADecl over the active window and later calls AOnCommand
  /// (control id, values JSON). False when no dialog can be shown now (another
  /// dialog is open, not over the panels).</summary>
  TPluginDialogHost = reference to function(const ADecl: TDialogDeclaration;
    const AOnCommand: TProc<string, string>): Boolean;

  /// <summary>Plugin-side answer: control id and values JSON.</summary>
  TPluginDialogCallback = reference to procedure(const AControlId, AValuesJson: string);

/// <summary>Registers (or, with nil, removes) the window that shows dialogs.</summary>
procedure SetPluginDialogHost(const AHost: TPluginDialogHost);

/// <summary>Shows a plugin dialog. ADeclJson is either the declaration itself
/// (starts with an opening brace) or the bare name of a file in the plugin's
/// own folder, plugins\&lt;id&gt;\dialogs\&lt;name&gt;.json. False when the JSON is not
/// a valid dialog declaration, the named file is missing, there is no host
/// window, or the host cannot show a dialog now. AOnCommand runs at most once,
/// on the main thread, and not at all after UnregisterPlugin(APluginId).</summary>
function PluginShowDialog(const APluginId, ADeclJson: string;
  const AOnCommand: TPluginDialogCallback): Boolean;

/// <summary>Drops the pending dialog callbacks of APluginId.</summary>
procedure PluginUiUnregister(const APluginId: string);

implementation

uses
  uDialogJson, uDialogResources;

const
  cMaxDeclarationChars = 256 * 1024;

var
  GHost: TPluginDialogHost;
  GGeneration: TDictionary<string, Integer>;

function GenerationOf(const APluginId: string): Integer;
begin
  if not GGeneration.TryGetValue(LowerCase(APluginId), Result) then
    Result := 0;
end;

procedure SetPluginDialogHost(const AHost: TPluginDialogHost);
begin
  GHost := AHost;
end;

function PluginShowDialog(const APluginId, ADeclJson: string;
  const AOnCommand: TPluginDialogCallback): Boolean;
var
  Decl: TDialogDeclaration;
  Gen: Integer;
  Id, Json: string;
  Answered: Boolean;
begin
  Result := False;
  Id := Trim(APluginId);
  if (Id = '') or not Assigned(GHost) or not Assigned(AOnCommand) then
    Exit;
  if (ADeclJson = '') or (Length(ADeclJson) > cMaxDeclarationChars) then
    Exit;
  Json := ADeclJson;
  if not TrimLeft(Json).StartsWith('{') then
    if not TryLoadPluginDialogJson(Id, Trim(Json), Json) then
      Exit;
  if not TryParseDialogJson(Json, Decl) then
    Exit;
  Gen := GenerationOf(Id);
  Answered := False;
  Result := GHost(Decl,
    procedure(AControlId, AValuesJson: string)
    begin
      if Answered or (GenerationOf(Id) <> Gen) then
        Exit;
      Answered := True;
      try
        AOnCommand(AControlId, AValuesJson);
      except
        // A faulty plugin callback must not break the host's dialog flow.
      end;
    end);
end;

procedure PluginUiUnregister(const APluginId: string);
var
  Key: string;
begin
  Key := LowerCase(Trim(APluginId));
  if Key = '' then
    Exit;
  GGeneration.AddOrSetValue(Key, GenerationOf(Key) + 1);
end;

initialization
  GGeneration := TDictionary<string, Integer>.Create;

finalization
  GHost := nil;
  FreeAndNil(GGeneration);

end.
