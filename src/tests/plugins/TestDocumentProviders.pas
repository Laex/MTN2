unit TestDocumentProviders;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDocumentProviders = class
  public
    [Test] procedure TestUriExtension;
    [Test] procedure TestAnswersAndRedirect;
    [Test] procedure TestExtensionsAndModesSelectProviders;
    [Test] procedure TestPriorityOrderAndPass;
    [Test] procedure TestFaultyProviderCountsAsPass;
    [Test] procedure TestInvalidRegistrationsAreIgnored;
    [Test] procedure TestOpenWithSystemRefusesNonLocalUris;
    [Test] procedure TestQuickViewAsksOnlyQuickProviders;
    [Test] procedure TestLazyLoadHookRunsBeforeTheProvidersAreAsked;
  end;

implementation

uses
  System.SysUtils,
  uDocumentProviders, uPluginHost;

procedure TestUriExtension;
begin
  Assert.IsTrue(DocumentUriExtension('file:///C:/Work/Note.MD') = '.md', 'lower-cased');
  Assert.IsTrue(DocumentUriExtension('file:///C:/Work.d/readme') = '', 'dot in a folder name');
  Assert.IsTrue(DocumentUriExtension('file:///C:/a.zip!/inner/f.txt') = '.txt', 'inside an archive');
  Assert.IsTrue(DocumentUriExtension('7z:///C:/a.7z!/doc.pdf') = '.pdf', 'plugin scheme');
  Assert.IsTrue(DocumentUriExtension('') = '', 'empty');
end;

procedure TestAnswersAndRedirect;
var
  Redirect: string;
begin
  try
    DocumentProviders.RegisterProvider('t.doc', 'a', '.foo', [dmView, dmEdit],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        ARedirectURI := 'file:///C:/tmp/rendered.txt';
        Result := dokRedirect;
      end);
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.foo', True, Redirect) = dokRedirect,
      'redirect answer');
    Assert.IsTrue(Redirect = 'file:///C:/tmp/rendered.txt', 'redirect target');

    DocumentProviders.RegisterProvider('t.doc', 'a', '.foo', [dmView, dmEdit],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Result := dokHandled;
      end);
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.foo', True, Redirect) = dokHandled,
      'the same provider id replaces its handler');
    Assert.IsTrue(Redirect = '', 'no redirect for a handled file');

    DocumentProviders.RegisterProvider('t.doc', 'a', '.foo', [dmView],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Result := dokRedirect;
      end);
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.foo', True, Redirect) = dokPass,
      'a redirect without a target is a pass');

    DocumentProviders.UnregisterPlugin('t.doc');
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.foo', True, Redirect) = dokPass,
      'unregistering drops the provider');
  finally
    DocumentProviders.UnregisterPlugin('t.doc');
  end;
end;

procedure TestExtensionsAndModesSelectProviders;
var
  Redirect, Seen: string;
begin
  Seen := '';
  try
    DocumentProviders.RegisterProvider('t.doc', 'view', 'md; .Markdown', [dmView],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Seen := Seen + 'view;';
        Result := dokHandled;
      end);
    DocumentProviders.RegisterProvider('t.doc', 'edit', '.txt', [dmEdit],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Seen := Seen + 'edit;';
        Result := dokHandled;
      end);
    DocumentProviders.RegisterProvider('t.doc', 'all', '*', [dmView, dmEdit],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Seen := Seen + 'all;';
        Result := dokPass;
      end, 500);

    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/n.markdown', True, Redirect) = dokHandled,
      'list with ; separator and no leading dot');
    Assert.IsTrue(Seen = 'view;', 'the view provider matched .markdown');
    Seen := '';
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/n.md', False, Redirect) = dokPass,
      'the view-only provider is not asked for the editor');
    Assert.IsTrue(Seen = 'all;', 'only the wildcard provider saw the edit: ' + Seen);
    Seen := '';
    DocumentProviders.TryOpen('file:///C:/n.txt', False, Redirect);
    Assert.IsTrue(Seen = 'edit;', 'the edit provider matched .txt');
    Seen := '';
    DocumentProviders.TryOpen('file:///C:/noext', True, Redirect);
    Assert.IsTrue(Seen = 'all;', 'a file without an extension only matches *');
  finally
    DocumentProviders.UnregisterPlugin('t.doc');
  end;
end;

procedure TestPriorityOrderAndPass;
var
  Order: string;
  Redirect: string;
begin
  Order := '';
  try
    DocumentProviders.RegisterProvider('t.late', 'p', '.bar', [dmView],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Order := Order + 'late;';
        Result := dokHandled;
      end, 300);
    DocumentProviders.RegisterProvider('t.early', 'p', '.bar', [dmView],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Order := Order + 'early;';
        Result := dokPass;
      end, 10);
    DocumentProviders.RegisterProvider('t.mid', 'p', '.bar', [dmView],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Order := Order + 'mid;';
        Result := dokHandled;
      end, 100);
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.bar', True, Redirect) = dokHandled,
      'handled');
    Assert.IsTrue(Order = 'early;mid;', 'ascending priority, stops at the first answer: ' + Order);
  finally
    DocumentProviders.UnregisterPlugin('t.late');
    DocumentProviders.UnregisterPlugin('t.early');
    DocumentProviders.UnregisterPlugin('t.mid');
  end;
end;

procedure TestFaultyProviderCountsAsPass;
var
  Redirect: string;
begin
  try
    DocumentProviders.RegisterProvider('t.boom', 'p', '.baz', [dmView],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        raise Exception.Create('plugin failure');
      end, 1);
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.baz', True, Redirect) = dokPass,
      'a provider that raises lets the built-in window open the file');
    DocumentProviders.RegisterProvider('t.ok', 'p', '.baz', [dmView],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Result := dokHandled;
      end, 2);
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.baz', True, Redirect) = dokHandled,
      'the next provider still runs after one raised');
  finally
    DocumentProviders.UnregisterPlugin('t.boom');
    DocumentProviders.UnregisterPlugin('t.ok');
  end;
end;

procedure TestInvalidRegistrationsAreIgnored;
var
  Redirect: string;
  Handler: TDocumentOpenHandler;
begin
  Handler :=
    function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
    begin
      Result := dokHandled;
    end;
  try
    DocumentProviders.RegisterProvider('', 'p', '.qux', [dmView], Handler);
    DocumentProviders.RegisterProvider('t.bad', 'p', '', [dmView], Handler);
    DocumentProviders.RegisterProvider('t.bad', 'p', ' , ;', [dmView], Handler);
    DocumentProviders.RegisterProvider('t.bad', 'p', '.qux', [], Handler);
    DocumentProviders.RegisterProvider('t.bad', 'p', '.qux', [dmView], nil);
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.qux', True, Redirect) = dokPass,
      'no invalid registration took effect');
  finally
    DocumentProviders.UnregisterPlugin('t.bad');
  end;
end;

procedure TestQuickViewAsksOnlyQuickProviders;
var
  Redirect, Asked: string;
  SawQuick: Boolean;
begin
  SawQuick := False;
  try
    DocumentProviders.RegisterProvider('t.viewonly', 'p', '.qv', [dmView],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        ARedirectURI := 'file:///C:/tmp/wrong.txt';
        Result := dokRedirect;
      end);
    Assert.IsFalse(DocumentProviders.TryQuickRedirect('file:///C:/x.qv', Redirect),
      'a provider without the quick mode is not asked');
    DocumentProviders.RegisterProvider('t.quick', 'p', '.qv', [dmView, dmQuick],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        SawQuick := DocumentQuickViewActive;
        ARedirectURI := 'file:///C:/tmp/text.txt';
        Result := dokRedirect;
      end);
    Assert.IsTrue(DocumentProviders.TryQuickRedirect('file:///C:/x.qv', Redirect), 'redirect');
    Assert.AreEqual('file:///C:/tmp/text.txt', Redirect);
    Assert.IsTrue(SawQuick, 'the handler can tell Quick View from F3');
    Assert.IsFalse(DocumentQuickViewActive, 'the flag is cleared afterwards');
    SawQuick := False;
    DocumentProviders.TryOpen('file:///C:/x.qv', True, Redirect);
    Assert.IsFalse(SawQuick, 'F3 runs the handler outside the quick mode');
    DocumentProviders.UnregisterPlugin('t.quick');
    Asked := '';
    DocumentProviders.RegisterProvider('t.quick', 'p', '.qv', [dmQuick],
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      begin
        Asked := AURI;
        if AURI.EndsWith('#view') then
          Result := dokHandled
        else
          Result := dokPass;
      end);
    Assert.IsTrue(DocumentProviders.TryQuickInteractive('file:///C:/x.qv'), 'handled');
    Assert.AreEqual('file:///C:/x.qv#view', Asked, 'the interactive view is asked for in the fragment');
  finally
    DocumentProviders.UnregisterPlugin('t.viewonly');
    DocumentProviders.UnregisterPlugin('t.quick');
  end;
end;

procedure TestOpenWithSystemRefusesNonLocalUris;
begin
  Assert.IsTrue(not OpenUriWithSystem('sftp://u@h/a.txt'), 'remote scheme');
  Assert.IsTrue(not OpenUriWithSystem('7z:///C:/a.7z!/f.txt'), 'plugin scheme');
  Assert.IsTrue(not OpenUriWithSystem(''), 'empty');
  Assert.IsTrue(not OpenUriWithSystem('file:///C:/no-such-dir-mtn2/none.txt'), 'missing file');
end;

{ TTestDocumentProviders }

procedure TTestDocumentProviders.TestUriExtension;
begin
  TestDocumentProviders.TestUriExtension;
end;

procedure TTestDocumentProviders.TestAnswersAndRedirect;
begin
  TestDocumentProviders.TestAnswersAndRedirect;
end;

procedure TTestDocumentProviders.TestExtensionsAndModesSelectProviders;
begin
  TestDocumentProviders.TestExtensionsAndModesSelectProviders;
end;

procedure TTestDocumentProviders.TestPriorityOrderAndPass;
begin
  TestDocumentProviders.TestPriorityOrderAndPass;
end;

procedure TTestDocumentProviders.TestFaultyProviderCountsAsPass;
begin
  TestDocumentProviders.TestFaultyProviderCountsAsPass;
end;

procedure TTestDocumentProviders.TestInvalidRegistrationsAreIgnored;
begin
  TestDocumentProviders.TestInvalidRegistrationsAreIgnored;
end;

procedure TTestDocumentProviders.TestOpenWithSystemRefusesNonLocalUris;
begin
  TestDocumentProviders.TestOpenWithSystemRefusesNonLocalUris;
end;

procedure TestLazyLoadHookRunsBeforeTheProvidersAreAsked;
var
  Redirect, Asked: string;
begin
  try
    SetDocumentLazyLoad(
      function(const AURI: string): Boolean
      begin
        Asked := AURI;
        DocumentProviders.RegisterProvider('t.lazy', 'a', '.foo', [dmView],
          function(const AU: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
          begin
            Result := dokHandled;
          end);
        Result := True;
      end);
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x.foo', True, Redirect) = dokHandled,
      'a provider registered by the hook answers the same call');
    Assert.IsTrue(Asked = 'file:///C:/x.foo', 'the hook gets the URI');
  finally
    SetDocumentLazyLoad(HostEnsureDocumentFile);
    DocumentProviders.UnregisterPlugin('t.lazy');
  end;
end;

procedure TTestDocumentProviders.TestLazyLoadHookRunsBeforeTheProvidersAreAsked;
begin
  TestDocumentProviders.TestLazyLoadHookRunsBeforeTheProvidersAreAsked;
end;

procedure TTestDocumentProviders.TestQuickViewAsksOnlyQuickProviders;
begin
  TestDocumentProviders.TestQuickViewAsksOnlyQuickProviders;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDocumentProviders);

end.
