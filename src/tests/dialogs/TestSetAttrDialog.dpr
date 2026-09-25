program TestSetAttrDialog;

{$APPTYPE CONSOLE}
{$R '..\..\MTN2.dres'}

{ Ctrl+Shift+A dialog (TFileOpDialogController, setattr.json): the
  Created / Modified / Accessed fields. Buttons "Current" / "Original" and a
  typo keep the dialog open (and claim the dialog kind back from the host);
  only fields the user actually changed end up in the plan. Works on
  throw-away files in %TEMP%. }

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uWinFileAttr,
  uDualPanelFileDialogs;

var
  GApplyCount: Integer;
  GPlan: TFileAttrPlan;
  GPaths: TArray<string>;
  GLastKind: THostDialogKind;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function MakeController(ADialog: TDialogHost): TFileOpDialogController;
begin
  Result := TFileOpDialogController.Create(ADialog,
    procedure(const AControlId, AValuesJson: string) begin end,
    procedure(AKind: THostDialogKind) begin GLastKind := AKind; end,
    procedure begin end,
    nil, nil, nil, nil, nil, nil, nil, nil, nil,
    nil, nil, nil, nil, nil, nil,
    procedure(const APaths: TArray<string>; const APlan: TFileAttrPlan)
    begin
      Inc(GApplyCount);
      GPaths := APaths;
      GPlan := APlan;
    end);
end;

procedure SetTimes(const APath: string; ACreated, AModified: TDateTime);
var
  Plan: TFileAttrPlan;
  Err: string;
begin
  Plan := Default(TFileAttrPlan);
  Plan.SetCreated := True;
  Plan.Times.Created := ACreated;
  Plan.SetModified := True;
  Plan.Times.Modified := AModified;
  if not ApplyFileAttrPlan(APath, Plan, Err) then
    raise Exception.Create('fixture: ' + Err);
end;

procedure Run;
var
  Dir, A, B: string;
  Dialog: TDialogHost;
  C: TFileOpDialogController;
  T1, T2, NewTime: TDateTime;
  NowText: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-setattr-dlg-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  A := TPath.Combine(Dir, 'a.txt');
  B := TPath.Combine(Dir, 'b.txt');
  T1 := EncodeDateTime(2020, 1, 2, 3, 4, 5, 0);
  T2 := EncodeDateTime(2021, 6, 7, 8, 9, 10, 0);
  Dialog := TDialogHost.Create(nil);
  C := MakeController(Dialog);
  try
    TFile.WriteAllText(A, 'a', TEncoding.UTF8);
    TFile.WriteAllText(B, 'b', TEncoding.UTF8);
    SetTimes(A, T1, T2);
    SetTimes(B, T2, T2);

    Writeln('One file: fields show its times');
    C.BeginSetAttributes([A]);
    Expect(Dialog.Visible, 'dialog opens');
    Expect(Dialog.GetInputValue('date_created') = FormatFileAttrTime(T1), 'created shown');
    Expect(Dialog.GetInputValue('date_modified') = FormatFileAttrTime(T2), 'modified shown');
    Expect(Dialog.GetInputValue('date_accessed') <> '', 'accessed shown');

    Writeln('"Current" and "Original" keep the dialog open');
    GLastKind := hdkNone;
    C.DispatchCommand(hdkSetAttributes, 'dates_now');
    NowText := Dialog.GetInputValue('date_modified');
    Expect(Dialog.Visible and (GLastKind = hdkSetAttributes), 'Current: still open, kind claimed back');
    Expect((NowText <> FormatFileAttrTime(T2)) and
      (Dialog.GetInputValue('date_created') = NowText) and
      (Dialog.GetInputValue('date_accessed') = NowText), 'Current fills all three with now');
    C.DispatchCommand(hdkSetAttributes, 'dates_orig');
    Expect(Dialog.Visible and
      (Dialog.GetInputValue('date_created') = FormatFileAttrTime(T1)) and
      (Dialog.GetInputValue('date_modified') = FormatFileAttrTime(T2)),
      'Original restores what the dialog opened with');

    Writeln('A typo keeps the dialog open, nothing applied');
    GApplyCount := 0;
    GLastKind := hdkNone;
    Dialog.SetInputValue('date_modified', '31.31.2020 99:99');
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Expect(Dialog.Visible and (GApplyCount = 0) and (GLastKind = hdkSetAttributes),
      'invalid date: open, not applied');

    Writeln('Only the changed field is written');
    NewTime := EncodeDateTime(2019, 11, 12, 13, 14, 15, 0);
    Dialog.SetInputValue('date_modified', FormatFileAttrTime(NewTime));
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Expect(not Dialog.Visible and (GApplyCount = 1), 'OK closes and applies');
    Expect(GPlan.SetModified and SameDateTime(GPlan.Times.Modified, NewTime),
      'modified goes into the plan');
    Expect(not GPlan.SetCreated and not GPlan.SetAccessed,
      'untouched created / accessed are not rewritten');

    // The attribute drop-downs open on the file's current values (Set /
    // Clear, not Keep), so OK may still apply those -- unchanged, and
    // ApplyFileAttributesOnly skips them. What matters here: no time.
    Writeln('Unchanged date fields write no time');
    GApplyCount := 0;
    GPlan := Default(TFileAttrPlan);
    C.BeginSetAttributes([A]);
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Expect(not Dialog.Visible, 'OK closes');
    Expect(not (GPlan.SetCreated or GPlan.SetModified or GPlan.SetAccessed),
      'untouched fields put no time into the plan');

    Writeln('Several files: differing times are empty = keep');
    C.BeginSetAttributes([A, B]);
    Expect(Dialog.GetInputValue('date_created') = '', 'created differs -> empty');
    Expect(Dialog.GetInputValue('date_modified') = FormatFileAttrTime(T2), 'modified equal -> shown');
    GPlan := Default(TFileAttrPlan);
    C.DispatchCommand(hdkSetAttributes, 'ok');
    Expect(not (GPlan.SetCreated or GPlan.SetModified or GPlan.SetAccessed),
      'an empty field is "keep", not "set to nothing"');

    Writeln('Cancel');
    GApplyCount := 0;
    C.BeginSetAttributes([A]);
    Dialog.SetInputValue('date_modified', FormatFileAttrTime(NewTime));
    C.DispatchCommand(hdkSetAttributes, 'cancel');
    Expect(not Dialog.Visible and (GApplyCount = 0), 'cancel applies nothing');
  finally
    C.Free;
    Dialog.Free;
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

begin
  try
    Run;
    Writeln('All SetAttrDialog tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
