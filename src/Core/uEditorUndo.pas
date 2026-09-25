unit uEditorUndo;

{ Editor Undo/Redo Manager: Isolates text modification stack management
  from uEditorWindow.pas. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TEditorUndoEntry = record
    Lines: TArray<string>;
    Bytes: TBytes;
    HexMode: Boolean;
    CursorRow: Integer;
    CursorCol: Integer;
  end;

  /// <summary>Undo / Redo stack manager for TEditorWindow.</summary>
  TEditorUndoBuffer = class
  private
    FUndoStack: TList<TEditorUndoEntry>;
    FRedoStack: TList<TEditorUndoEntry>;
    FMaxItems: Integer;
    function GetUndoCount: Integer;
    function GetRedoCount: Integer;
  public
    constructor Create(AMaxItems: Integer = 100);
    destructor Destroy; override;
    procedure PushState(const AEntry: TEditorUndoEntry);
    procedure PushRedo(const AEntry: TEditorUndoEntry);
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function PopUndoState: TEditorUndoEntry;
    function PopRedoState: TEditorUndoEntry;
    procedure Clear;
    property UndoCount: Integer read GetUndoCount;
    property RedoCount: Integer read GetRedoCount;
  end;

implementation

constructor TEditorUndoBuffer.Create(AMaxItems: Integer);
begin
  inherited Create;
  FMaxItems := AMaxItems;
  FUndoStack := TList<TEditorUndoEntry>.Create;
  FRedoStack := TList<TEditorUndoEntry>.Create;
end;

destructor TEditorUndoBuffer.Destroy;
begin
  FUndoStack.Free;
  FRedoStack.Free;
  inherited Destroy;
end;

function TEditorUndoBuffer.GetUndoCount: Integer;
begin
  Result := FUndoStack.Count;
end;

function TEditorUndoBuffer.GetRedoCount: Integer;
begin
  Result := FRedoStack.Count;
end;

procedure TEditorUndoBuffer.PushState(const AEntry: TEditorUndoEntry);
begin
  FUndoStack.Add(AEntry);
  while FUndoStack.Count > FMaxItems do
    FUndoStack.Delete(0);
  FRedoStack.Clear;
end;

procedure TEditorUndoBuffer.PushRedo(const AEntry: TEditorUndoEntry);
begin
  FRedoStack.Add(AEntry);
end;

function TEditorUndoBuffer.CanUndo: Boolean;
begin
  Result := FUndoStack.Count > 0;
end;

function TEditorUndoBuffer.CanRedo: Boolean;
begin
  Result := FRedoStack.Count > 0;
end;

function TEditorUndoBuffer.PopUndoState: TEditorUndoEntry;
var
  LIdx: Integer;
begin
  LIdx := FUndoStack.Count - 1;
  Result := FUndoStack[LIdx];
  FUndoStack.Delete(LIdx);
end;

function TEditorUndoBuffer.PopRedoState: TEditorUndoEntry;
var
  LIdx: Integer;
begin
  LIdx := FRedoStack.Count - 1;
  Result := FRedoStack[LIdx];
  FRedoStack.Delete(LIdx);
end;

procedure TEditorUndoBuffer.Clear;
begin
  FUndoStack.Clear;
  FRedoStack.Clear;
end;

end.
