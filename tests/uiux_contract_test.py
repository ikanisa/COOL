"""UI/UX source/resource checks. These do NOT prove Android rendering or accessibility conformance."""
import hashlib,importlib.util,json,pathlib,re,unittest,xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[1]
NATIVE=ROOT/'native/burimunsi'; UI=NATIVE/'app/src/main/kotlin/rw/ikanisa/burimunsi/ui'
CAT=json.loads((ROOT/'contracts/ui-copy.json').read_text());COPY={e['en']:e for e in CAT['entries']}
PROTOTYPE=ROOT/'docs/implementation/burimunsi-android/prototype-reference'
ORIGINAL_MAP=json.loads((PROTOTYPE/'screen-map.json').read_text())
ORIGINAL_HTML=(PROTOTYPE/'index.html').read_text()
ORIGINAL_CONTRACT=json.loads((PROTOTYPE/'ui-contract.json').read_text())
PANEL_BINDINGS={'profile':'PROFILE','change-passcode':'PIN','help':'HELP','allocate':'ALLOCATE',
    'add-member':'ENROLL','staff-list':'STAFF','staff-edit':'STAFF_EDIT','confirm-remove':'REMOVE_STAFF',
    'gateway':'GATEWAY','raw':'RAW','member-details':'MEMBER_DETAILS','history-payment':'HISTORY',
    'audit':'AUDIT','filters':'FILTERS','replace-device':'REPLACE_DEVICE'}
spec=importlib.util.spec_from_file_location('uicopy',ROOT/'scripts/generate_ui_copy.py');generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)
def rgb(value):
    value=value.lstrip('#')
    if len(value)==3:value=''.join(c*2 for c in value)
    return tuple(int(value[i:i+2],16)/255 for i in (0,2,4))
def luminance(c):return sum(w*(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4) for w,v in zip((.2126,.7152,.0722),c))
def contrast(a,b):return (max(luminance(a),luminance(b))+.05)/(min(luminance(a),luminance(b))+.05)
def css_rule(selector):
    return re.search(re.escape(selector)+r'\{([^}]+)\}',ORIGINAL_HTML)[1]
def css_variables(selector):return dict(re.findall(r'--([\w-]+):([^;]+)',css_rule(selector)))
def css_colour(value):
    if value.startswith('#'):return (*rgb(value),1)
    match=re.fullmatch(r'rgba\((\d+),(\d+),(\d+),([\d.]+)\)',value)
    if match:return (*(int(match[i])/255 for i in (1,2,3)),float(match[4]))
    return css_colour(css_variables(':root')[re.fullmatch(r'var\(--([\w-]+)\)',value)[1]])
def native_colour(value):return (*rgb(value[2:]),int(value[:2],16)/255)
def composite(foreground,background):return tuple(foreground[i]*foreground[3]+background[i]*(1-foreground[3]) for i in range(3))
def prototype_route(route):
    base=css_variables(':root');overrides=css_variables('.phone[data-theme="'+route+'"]')
    colours={name:css_colour(overrides.get(name,base[name])) for name in ('text','muted','blue','good','warn','bad')}
    colours.update({name:css_colour(overrides.get(name,'var(--'+fallback+')')) for name,fallback in (('tone','raised'),('group','surface'))})
    stops=[(float(position)/100,rgb(value)) for value,position in re.findall(r'#([a-f\d]{3,6}) ([\d.]+)%',overrides['wash'])]
    return colours,stops or [(0,rgb(base['canvas'])),(1,rgb(base['canvas']))]
def native_route(route):
    theme=(UI/'Theme.kt').read_text()
    base={name.lower():(*rgb(value),1) for name,value in re.findall(r'val (\w+)=Color\(0xFF([0-9A-F]{6})\)',theme)}
    route_key='else' if route=='utility' else 'Route.'+route.upper()
    branch=re.search(re.escape(route_key)+r'->BuriRouteColors\(([^\n]+)\)',theme)[1]
    values=re.findall(r'Color\(0x([A-F\d]{8})\)|(Surface|Raised)',branch)
    base.update(zip(('muted','blue','tone','group'),[native_colour(value) if value else base[name.lower()] for value,name in values]))
    if route=='utility':return base,[(0,base['canvas'][:3]),(1,base['canvas'][:3])]
    wash=theme.split('fun wash(route:Route)',1)[1]
    branch=re.search(re.escape(route_key)+r'->Brush.verticalGradient\(([^\n]+)\)',wash)[1]
    stops=[(float(position),rgb(value) if value else base['canvas'][:3]) for position,value in re.findall(r'([\d.]+)f to (?:Color\(0xFF([A-F\d]{6})\)|Canvas)',branch)]
    return base,stops
def contrast_evidence():
    """Source-only bounds, using each route's actual wash/group/tone rather than invented white glass."""
    evidence={}
    for route in ('home','payments','members','sms','login','utility'):
        evidence[route]={}
        for source,read in (('original',prototype_route),('native',native_route)):
            colours,stops=read(route)
            backgrounds=[background for _,background in stops]
            backgrounds += [composite(colours[role],background) for _,background in stops for role in ('tone','group')]
            evidence[route][source]={name:round(min(contrast(colours[name][:3],background) for background in backgrounds),4) for name in ('text','muted','blue','good','warn','bad')}
    return evidence
class UiUxContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app_units = {name: (UI/name).read_text() for name in (
            'BuriApp.kt', 'BuriComponents.kt', 'BuriRecordsScreens.kt', 'BuriSmsScreen.kt',
            'BuriAccountScreens.kt', 'BuriSheetHost.kt', 'BuriOperationSheets.kt', 'BuriMemberEnrollmentSheet.kt',
        )}
        cls.app = '\n'.join(cls.app_units.values())
        cls.shell = cls.app_units['BuriApp.kt']
        cls.sheets = cls.app_units['BuriSheetHost.kt']
        cls.behavior = (UI/'UiBehavior.kt').read_text()
        cls.vm = (UI/'BuriViewModel.kt').read_text()
    def test_resources_regenerate_exactly(self):
        for path,text in generator.generated().items():self.assertEqual(path.read_text(),text,str(path))
    def test_both_languages_have_identical_resource_keys(self):
        keys=[]
        for directory in ('values','values-rw'):
            values=ET.parse(NATIVE/f'app/src/main/res/{directory}/ui_strings.xml').getroot()
            keys.append([e.attrib['name'] for e in values]);self.assertTrue(all(e.text for e in values))
        self.assertEqual(keys[0],keys[1]);self.assertEqual(len(keys[0]),len(CAT['entries']))
    def test_catalog_has_unique_phrases_and_placeholder_parity(self):
        self.assertEqual(len(COPY),len(CAT['entries']))
        for e in CAT['entries']:self.assertEqual(sorted(re.findall(r'%\d+\$[sd]',e['en'])),sorted(re.findall(r'%\d+\$[sd]',e['rw'])),e['en'])
    def test_all_financial_presentation_copy_is_localized(self):
        source=(NATIVE/'core/src/main/kotlin/rw/ikanisa/burimunsi/core/Presentation.kt').read_text()
        for phrase in re.findall(r'"([A-Z][^"\n]+)"',source):self.assertIn(phrase,COPY)
    def test_all_receiving_phone_diagnostics_are_localized(self):
        source=(NATIVE/'core/src/main/kotlin/rw/ikanisa/burimunsi/core/GatewayHealth.kt').read_text()
        for phrase in re.findall(r'"([A-Z][^"\n]+)"',source):self.assertIn(phrase,COPY)
    def test_controller_error_copy_is_localized(self):
        # Fixed audited API payloads are not user-facing copy and must not be translated.
        audit_purposes={'Review original SMS from the selected contribution or receipt','Automatic SMS list preview'}
        self.assertIn('if(sheet==Sheet.RAW)loadRawForCurrentPanel("Review original SMS from the selected contribution or receipt")',self.vm)
        inbox = (UI/'NativeSmsInboxScan.kt').read_text()
        self.assertIn('val reason = "Automatic SMS list preview"', inbox)
        self.assertIn('is SmsSourceRef.Canonical -> repository().raw(source.id, reason)', inbox)
        self.assertIn('is SmsSourceRef.Observation -> repository().revealObservation(source, reason)', inbox)
        sources = (
            ('BuriViewModel.kt', self.vm),
            ('NativeListingDownloads.kt', (UI/'NativeListingDownloads.kt').read_text()),
            ('NativeSmsDisclosure.kt', (UI/'NativeSmsDisclosure.kt').read_text()),
            ('NativeSmsInboxScan.kt', inbox),
        )
        for name, source in sources:
            for phrase in re.findall(r'"([A-Z][^"\n]+)"', source):
                if ' ' in phrase and '$' not in phrase and phrase not in audit_purposes:
                    self.assertIn(phrase, COPY, f'{name}: {phrase}')
    def test_restored_original_ui_copy_is_localized(self):
        for name,source in list(self.app_units.items())+[(name,(UI/name).read_text()) for name in ('UiFeedback.kt','UiListingTools.kt','UiPreferences.kt')]:
            for literal in re.findall(r'\bt\(\s*("(?:[^"\\]|\\.)*")',source):
                phrase=json.loads(literal.replace('\\$','$'))
                self.assertIn(phrase,COPY,name+': '+phrase)
        # Static alternatives rendered through t(if...), t(rawError), and the status select.
        for phrase in ('Admin','Staff','Gateway','Pair receiver','Create staff','Save changes','Disable','Enable',
            'All messages are synced.','Try another search.','Original SMS unavailable.',
            'Verified','Changed · sync blocked','Required','Granted','Blocked','Listening','Paused','Pause','Resume',
            'All','Allocated','Unallocated','Processing'):
            self.assertIn(phrase,COPY,phrase)
    def test_direct_text_literals_are_brand_or_decorative(self):
        brands={'BuriMunsi','BuriMunsi · Collect'}
        for brand in brands:self.assertIn(brand,ORIGINAL_HTML)
        # This icon is decorative and explicitly removed from accessibility semantics.
        self.assertIn('Text("+",Modifier.clearAndSetSemantics{}',self.app)
        self.assertLessEqual(set(re.findall(r'\bText\("([^"\n]+)"',self.app)),brands|{'+'})
    def test_sanitized_prototype_reference_is_byte_exact(self):
        provenance=json.loads((PROTOTYPE/'provenance.json').read_text())
        self.assertEqual(provenance['prototype_name'],'BuriMunsi_Prototype_v1.1.0.html')
        for item in provenance['files']:
            data=(PROTOTYPE/item['path']).read_bytes()
            self.assertEqual(len(data),item['bytes'])
            self.assertEqual(hashlib.sha256(data).hexdigest(),item['sha256'])
        prototype=next(item for item in provenance['files'] if item['path']=='index.html')
        self.assertEqual(prototype['sha256'], '3f2d159b139f1e39adb96bfafe739d044bb9ebfd836cc9c15d73d009b0744a97')
        self.assertEqual(prototype['original_sha256'], '644c0ca7dfa38ee184a80be7d0e0d753503fa40dac00ae1814a9359b5e9fba4d')
    def test_original_phone_pin_entry_has_no_added_onboarding_screen(self):
        activity=(NATIVE/'app/src/main/kotlin/rw/ikanisa/burimunsi/MainActivity.kt').read_text()
        self.assertIn('BuriApp(',activity)
        for added in ('PhoneSetup(', 'CollectSignIn(', 'InstallationSetupDetails('):
            self.assertNotIn(added,activity)
            self.assertNotIn('fun '+added,self.app)
    def test_raw_evidence_and_names_are_not_sent_to_translation(self):
        for value in ('raw.body','raw.sender','raw.at','p.ftId','p.payerNameRaw','p.payerPhoneRaw','p.atRaw','sms.preview','member.name','member.phone'):
            self.assertNotIn('t('+value+')',self.app)
        self.assertIn('SelectionContainer{Text(raw.body',self.app)
    def test_supported_languages_are_explicit(self):
        root=ET.parse(NATIVE/'app/src/main/res/xml/locales_config.xml').getroot()
        self.assertEqual({e.attrib['{http://schemas.android.com/apk/res/android}name'] for e in root},{'en','rw'})
    def test_display_preferences_never_store_operator_data(self):
        source=(UI/'UiPreferences.kt').read_text()
        self.assertEqual(set(re.findall(r'put(?:String|Boolean)\("([^"]+)"',source)),{'language','reduce-screen-motion'})
    def test_navigation_store_uses_existing_encrypted_boundary(self):
        source=(NATIVE/'app/src/main/kotlin/rw/ikanisa/burimunsi/storage/AndroidNavigationCheckpointStore.kt').read_text()
        self.assertIn('SecureStore(context, "ui-navigation")',source);self.assertNotIn('getSharedPreferences(',source)
    def test_no_sensitive_saveable_state(self):
        self.assertNotIn('rememberSaveable',self.app);self.assertNotIn('SavedStateHandle',self.vm)
        self.assertIn('state.selectedMember',self.vm);self.assertIn('draft=emptyMap()',self.vm)
    def test_all_original_routes_are_rendered(self):
        body=self.shell.split('RouteEntrance(t(titleFor(s.route))){when(s.route){',1)[1].split('}}}',1)[0]
        expected={screen['route'].upper() for screen in ORIGINAL_MAP['screens']}
        self.assertEqual(set(re.findall(r'Route\.(\w+)->',body)),expected)
    def test_all_original_panels_are_rendered(self):
        panel_body=self.sheets.split('key(sheet,s.sheetId){when(sheet)',1)[1].split('@Composable private fun DiscardPrompt',1)[0]
        expected={panel for screen in ORIGINAL_MAP['screens'] for panel in screen['panels']}
        self.assertEqual(set(PANEL_BINDINGS),expected)
        self.assertEqual(set(re.findall(r'Sheet\.(\w+)->',panel_body)),{PANEL_BINDINGS[x] for x in expected})
    def test_reduced_motion_does_not_keep_outgoing_records(self):
        self.assertIn('progress.snapTo(1f)',self.behavior);self.assertIn('tween(160)',self.behavior)
        self.assertNotIn('Crossfade(',self.behavior);self.assertNotIn('AnimatedContent(',self.behavior)
    def test_ime_chains_and_secret_disposal_are_explicit(self):
        self.assertIn('nextFocus.requestFocus()',self.app);self.assertIn('Key.NumPadEnter',self.app)
        self.assertIn('if(imeVisible){keyboard?.hide();focus.clearFocus()}',self.app)
        self.assertIn('pin=""',self.app);self.assertIn('current="";next="";confirm=""',self.app)
    def test_signin_has_no_undefined_pending_variable(self):
        login=self.app_units['BuriAccountScreens.kt'].split('fun Login(',1)[1].split('@Composable',1)[0]
        self.assertNotIn('pending',login)
    def test_modal_dirty_dismissal_is_vetoed(self):
        self.assertIn('confirmValueChange={target->',self.sheets)
        self.assertIn('latest.value.busy||latest.value.draftDirty',self.sheets)
        self.assertIn('rememberLazyListState(position.first,position.second)',self.app_units['BuriComponents.kt'])
    def test_original_small_text_roles_and_amount_floor(self):
        original_floor=int(re.search(r'font-size:calc\((\d+)px',css_rule('.tiny'))[1])
        original_count=int(re.search(r'font-size:calc\((\d+)px',css_rule('.countline'))[1])
        self.assertTrue(all(int(n)>=original_floor for n in re.findall(r'fontSize=(\d+)\.sp',self.app)))
        count_line=self.app_units['BuriComponents.kt'].split('fun CountLine(',1)[1].split('@Composable',1)[0]
        self.assertEqual(set(map(int,re.findall(r'fontSize=(\d+)\.sp',count_line))),{original_count})
        self.assertIn('Presentation.MONEY_MIN_SP',self.app);self.assertIn('fontFeatureSettings="tnum"',self.app)
        presentation=(NATIVE/'core/src/main/kotlin/rw/ikanisa/burimunsi/core/Presentation.kt').read_text()
        self.assertEqual(int(re.search(r'MONEY_MIN_SP\s*=\s*(\d+)',presentation)[1]),ORIGINAL_CONTRACT['money']['minimumFontSp'])
        # The original 390px phone keeps rows side by side; narrow/large-text fallback remains available.
        phone_width=int(re.search(r'width:(\d+)px',css_rule('.phone'))[1])
        inset=int(css_variables(':root')['inset'].removesuffix('px'))
        row_padding=int(re.search(r'padding:2px (\d+)px',css_rule('.rows'))[1])
        available=phone_width-2*inset-2*row_padding
        thresholds=list(map(int,re.findall(r'val stacked=maxWidth<(\d+)\.dp\|\|(?:LocalDensity.current\.)?fontScale>=1.5f',self.app)))
        self.assertEqual(len(thresholds),3)
        self.assertTrue(all(0<threshold<available for threshold in thresholds))
    def test_native_palette_and_route_washes_match_original_css(self):
        theme=(UI/'Theme.kt').read_text();base=css_variables(':root')
        self.assertEqual(float(re.search(r'WashScrimAlpha=([\d.]+)f',theme)[1]),0)
        self.assertIn('background-image:var(--wash)',css_rule('.phone'))
        native,_=native_route('utility')
        for name in ('canvas','surface','raised','text','good','warn','bad'):
            self.assertEqual(native[name],css_colour(base[name]),name)
        self.assertIn('else Color(0xFF'+base['input'][1:].upper()+')',theme)
        login_alpha=float(re.search(r'rgba\(0,0,0,([\d.]+)\)',css_rule('.login .field input'))[1])
        self.assertEqual(float(re.search(r'Route.LOGIN\)Color.Black.copy\(alpha=([\d.]+)f',theme)[1]),login_alpha)
        for route in ('home','payments','members','sms','login','utility'):
            original,original_stops=prototype_route(route);native,native_stops=native_route(route)
            self.assertEqual(native_stops,original_stops,route)
            for name in ('muted','blue','tone','group'):
                self.assertEqual(tuple(round(v*255) for v in native[name]),tuple(round(v*255) for v in original[name]),route+': '+name)
    def test_contrast_has_no_regression_against_original_route_colours(self):
        # CSS rgba values quantize to 8-bit alpha in Compose; allow only that bounded rounding.
        for route,values in contrast_evidence().items():
            for name,ratio in values['native'].items():
                self.assertAlmostEqual(ratio,values['original'][name],delta=.025,msg=route+': '+name)
    def test_utility_text_contrast_remains_at_least_45(self):
        colours,_=native_route('utility')
        for name in ('text','muted','blue','good','warn','bad'):
            for background in ('canvas','surface','raised'):
                self.assertGreaterEqual(contrast(colours[name][:3],colours[background][:3]),4.5,name+': '+background)
    def test_twelve_controller_journeys_have_distinct_ids(self):
        source=(NATIVE/'viewmodel-tests/JourneyChecks.kt').read_text()
        self.assertEqual(re.findall(r'journey\("(J\d+)"',source),[f'J{i:02}' for i in range(1,13)])
    def test_instrumentation_is_not_in_shipping_source(self):
        for p in (NATIVE/'app/src/main').rglob('*.kt'):self.assertNotIn('FakeController',p.read_text())
if __name__=='__main__':unittest.main()
