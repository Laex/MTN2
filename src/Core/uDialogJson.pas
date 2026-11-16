unit uDialogJson;

{ DIALOG_PLUGIN JSON subset <-> TDialogDeclaration (in-process seam for cdecl). }

interface

uses
  System.SysUtils,
  uDialogTypes;

function TryParseDialogJson(const AJson: string; out ADecl: TDialogDeclaration): Boolean;
function DeclarationToJson(const ADecl: TDialogDeclaration): string;

implementation

uses
  System.JSON, System.StrUtils, System.Generics.Collections,
  uDialogJsonParse, uDialogJsonSerialize;

function TryParseDialogJson(const AJson: string; out ADecl: TDialogDeclaration): Boolean;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  Kids: TJSONArray;
  List: TList<TDialogControl>;
  I: Integer;
  Child: TJSONValue;
begin
  Result := False;
  ADecl.Version := cDialogProtocolV1;
  ADecl.Title := '';
  ADecl.Width := 48;
  ADecl.Height := 8;
  ADecl.IsWarning := False;
  ADecl.NoAutoLayout := False;
  SetLength(ADecl.Controls, 0);
  if Trim(AJson) = '' then
    Exit;

  Root := TJSONObject.ParseJSONValue(AJson);
  if not Assigned(Root) then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    ADecl.Version := JsonStr(Obj, 'version', cDialogProtocolV1);
    if Trim(ADecl.Version) = '' then
      ADecl.Version := cDialogProtocolV1;
    ADecl.Title := JsonStr(Obj, 'title', 'Dialog');
    ADecl.Width := JsonInt(Obj, 'width', 48);
    ADecl.Height := JsonInt(Obj, 'height', 8);
    ADecl.IsWarning := SameText(JsonStr(Obj, 'style', ''), 'warning') or
      SameText(JsonStr(Obj, 'style', ''), 'error');
    if Assigned(Obj.Values['autoLayout']) then
      ADecl.NoAutoLayout := Obj.Values['autoLayout'] is TJSONFalse;
    if ADecl.Width < 28 then
      ADecl.Width := 28;
    if ADecl.Height < 6 then
      ADecl.Height := 6;

    List := TList<TDialogControl>.Create;
    try
      Kids := Obj.Values['children'] as TJSONArray;
      if Assigned(Kids) then
        for I := 0 to Kids.Count - 1 do
        begin
          Child := Kids.Items[I];
          if Child is TJSONObject then
            ParseControlObject(TJSONObject(Child), List);
        end
      else
        // Flat controls array fallback: { "controls": [ ... ] }
        begin
          Kids := Obj.Values['controls'] as TJSONArray;
          if Assigned(Kids) then
            for I := 0 to Kids.Count - 1 do
            begin
              Child := Kids.Items[I];
              if Child is TJSONObject then
                ParseControlObject(TJSONObject(Child), List);
            end;
        end;

      if List.Count = 0 then
        Exit;
      ADecl.Controls := List.ToArray;
      Result := True;
    finally
      List.Free;
    end;
  finally
    Root.Free;
  end;
end;


function DeclarationToJson(const ADecl: TDialogDeclaration): string;
begin
  Result := uDialogJsonSerialize.DeclarationToJson(ADecl);
end;

end.