program TestUserAssociations;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  uShellAssoc in '..\..\Core\uShellAssoc.pas',
  uAssociations in '..\..\Core\uAssociations.pas',
  uUserAssociations in '..\..\Core\uUserAssociations.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestNormalizeAndCommand;
begin
  Writeln('NormalizeAssocExtension / BuildAssocCommandLine');
  Expect(NormalizeAssocExtension('readme.LOG') = '.log', 'lowercased, leading dot');
  Expect(NormalizeAssocExtension('.iso') = '.iso', 'already normalized');
  Expect(BuildAssocCommandLine('tool.exe "%1"', 'C:\a b\f.iso') =
    'tool.exe ""C:\a b\f.iso""', 'placeholder substitution keeps template quoting');
  Expect(BuildAssocCommandLine('tool.exe %1', 'C:\f.iso') = 'tool.exe "C:\f.iso"',
    'unquoted placeholder gets a quoted path');
  Expect(BuildAssocCommandLine('tool.exe', 'C:\f.iso') = 'tool.exe "C:\f.iso"',
    'no placeholder appends the quoted path');
end;

procedure TestRuleListManagement;
var
  Assoc: TUserAssociations;
  Rule: TUserAssocRule;
begin
  Writeln('TUserAssociations rule management');
  Assoc := TUserAssociations.Create;
  try
    Expect(Assoc.Count = 0, 'starts empty');
    Expect(not Assoc.TryResolve('a.log', Rule), 'no rule yet');

    Rule.Extension := '.LOG';
    Rule.Action := uaaShell;
    Rule.Command := '';
    Assoc.AddRule(Rule);
    Expect(Assoc.Count = 1, 'one rule added');
    Expect(Assoc.GetRule(0).Extension = '.log', 'extension normalized on add');
    Expect(Assoc.TryResolve('anything.log', Rule) and (Rule.Action = uaaShell),
      'resolves by normalized extension');

    Rule.Extension := '.log';
    Rule.Action := uaaCommand;
    Rule.Command := 'less.exe %1';
    Assoc.SetRuleForExtension(Rule);
    Expect(Assoc.Count = 1, 'upsert replaces, does not duplicate');
    Expect(Assoc.TryResolve('x.log', Rule) and (Rule.Action = uaaCommand) and
      (Rule.Command = 'less.exe %1'), 'upsert updated the existing rule');

    Rule.Extension := '.iso';
    Rule.Action := uaaView;
    Assoc.SetRuleForExtension(Rule);
    Expect(Assoc.Count = 2, 'upsert of a new extension appends');

    Assoc.DeleteRule(Assoc.IndexOfExtension('.log'));
    Expect(Assoc.Count = 1, 'delete removes one rule');
    Expect(not Assoc.TryResolve('x.log', Rule), 'deleted rule no longer resolves');
  finally
    Assoc.Free;
  end;
end;

procedure TestRoundTrip;
var
  Assoc, Loaded: TUserAssociations;
  Path: string;
  Rule: TUserAssocRule;
begin
  Writeln('Save/Load round trip');
  Path := TPath.Combine(TPath.GetTempPath,
    'mtn2-user-assoc-test-' + IntToStr(Random(MaxInt)) + '.json');
  Assoc := TUserAssociations.Create;
  Loaded := TUserAssociations.Create;
  try
    Rule.Extension := '.log'; Rule.Action := uaaShell; Rule.Command := '';
    Assoc.AddRule(Rule);
    Rule.Extension := '.iso'; Rule.Action := uaaCommand; Rule.Command := 'mount.exe "%1"';
    Assoc.AddRule(Rule);

    Expect(SaveUserAssociations(Path, Assoc), 'save succeeds');
    Expect(TryLoadUserAssociations(Path, Loaded), 'load succeeds');
    Expect(Loaded.Count = 2, 'round-tripped rule count');
    Expect(Loaded.TryResolve('a.log', Rule) and (Rule.Action = uaaShell), 'shell rule round-trips');
    Expect(Loaded.TryResolve('a.iso', Rule) and (Rule.Action = uaaCommand) and
      (Rule.Command = 'mount.exe "%1"'), 'command + template round-trip');

    // Missing file: load must not fail, must reset to empty (matches
    // uSession.TryLoadSession's "missing file = defaults" contract).
    TFile.Delete(Path);
    Expect(not TryLoadUserAssociations(Path, Loaded), 'missing file returns False');
    Expect(Loaded.Count = 0, 'missing file resets to empty, does not keep stale rules');

    // Corrupt file: must not raise, must not leave stale rules either.
    TFile.WriteAllText(Path, 'not json{{{', TEncoding.UTF8);
    Expect(not TryLoadUserAssociations(Path, Loaded), 'corrupt file returns False');
    Expect(Loaded.Count = 0, 'corrupt file resets to empty');
  finally
    Assoc.Free;
    Loaded.Free;
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

procedure TestResolveWithUserRules;
var
  Assoc: TUserAssociations;
  Cmd: string;
  Rule: TUserAssocRule;
begin
  Writeln('ResolveAssociationWithUserRules');
  Assoc := GlobalUserAssociations;
  Assoc.Clear;

  // No user rule: falls through to the built-in table (.pas is aaEdit).
  Expect(ResolveAssociationWithUserRules('main.pas', False, Cmd) = aaEdit,
    'no user rule falls back to built-in table');

  // A user rule overrides the built-in table for the same extension
  // (.pas would otherwise be aaEdit).
  Rule.Extension := '.pas';
  Rule.Action := uaaView;
  Rule.Command := '';
  Assoc.AddRule(Rule);
  Expect(ResolveAssociationWithUserRules('main.pas', False, Cmd) = aaView,
    'user rule overrides the built-in table');

  // A uaaCommand rule surfaces aaCommand + the raw template via the out param.
  Rule.Extension := '.iso';
  Rule.Action := uaaCommand;
  Rule.Command := 'mount.exe "%1"';
  Assoc.AddRule(Rule);
  Expect((ResolveAssociationWithUserRules('disk.iso', False, Cmd) = aaCommand) and
    (Cmd = 'mount.exe "%1"'), 'command rule surfaces aaCommand + template');

  // Executables always win, even if the user (mis)configures a rule for them
  // -- matches Far/TC/NDN priority 1 (launchables never overridable).
  Rule.Extension := '.exe';
  Rule.Action := uaaView;
  Rule.Command := '';
  Assoc.AddRule(Rule);
  Expect(ResolveAssociationWithUserRules('tool.exe', False, Cmd) = aaShell,
    'launchable extensions stay aaShell regardless of a user rule');

  // Directories always navigate, user rules do not apply to them.
  Expect(ResolveAssociationWithUserRules('somedir', True, Cmd) = aaNavigate,
    'directories always navigate');

  Assoc.Clear;
end;

begin
  Randomize;
  try
    TestNormalizeAndCommand;
    TestRuleListManagement;
    TestRoundTrip;
    TestResolveWithUserRules;
    Writeln('All UserAssociations tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
