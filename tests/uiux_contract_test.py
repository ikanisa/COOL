"""UI/UX source/resource checks. These do NOT prove Android rendering or accessibility conformance."""
import importlib.util,json,pathlib,re,unittest,xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[1]
NATIVE=ROOT/'native/burimunsi'; UI=NATIVE/'app/src/main/kotlin/rw/ikanisa/burimunsi/ui'
CAT=json.loads((ROOT/'contracts/ui-copy.json').read_text());COPY={e['en']:e for e in CAT['entries']}
spec=importlib.util.spec_from_file_location('uicopy',ROOT/'scripts/generate_ui_copy.py');generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)
def rgb(value):return [int(value[i:i+2],16)/255 for i in (0,2,4)]
def luminance(c):return sum(w*(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4) for w,v in zip((.2126,.7152,.0722),c))
def contrast(a,b):return (max(luminance(a),luminance(b))+.05)/(min(luminance(a),luminance(b))+.05)
def contrast_evidence():
    theme=(UI/'Theme.kt').read_text()
    tokens={name:rgb(value) for name,value in re.findall(r'val (\w+)=Color\(0xFF([0-9A-F]{6})\)',theme)}
    alpha=float(re.search(r'WashScrimAlpha=(\.\d+)f',theme)[1])
    wash=theme.split('fun wash(route:Route)',1)[1].split('/** Optional',1)[0]
    backgrounds=[[(1-alpha)*v for v in rgb(value)] for value in re.findall(r'Color\(0xFF([0-9A-F]{6})\)',wash)]
    backgrounds+=[tokens[name] for name in ('Canvas','Surface','Raised','Input')]
    backgrounds=[[(1-glass)*v+glass for v in bg] for bg in backgrounds for glass in (0,.08,.09,.11,.12)]
    return {name:round(min(contrast(tokens[name],bg) for bg in backgrounds),4) for name in ('Text','Muted','Blue','Good','Warn','Bad')}
class UiUxContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app=(UI/'BuriApp.kt').read_text();cls.behavior=(UI/'UiBehavior.kt').read_text();cls.vm=(UI/'BuriViewModel.kt').read_text()
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
        for phrase in re.findall(r'"([A-Z][^"\n]+)"',self.vm):
            if ' ' in phrase and '$' not in phrase:self.assertIn(phrase,COPY,phrase)
    def test_direct_text_literals_are_brand_only(self):
        self.assertEqual(set(re.findall(r'\bText\("([^"\n]+)"',self.app)),{'BuriMunsi'})
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
    def test_all_eight_routes_are_rendered(self):
        body=self.app.split('RouteEntrance',1)[1].split('if(read&&',1)[0]
        self.assertEqual(set(re.findall(r'Route\.(\w+)->',body)),{'LOGIN','HOME','PAYMENTS','PAYMENT','MEMBERS','MEMBER','SMS','SETTINGS'})
    def test_all_fourteen_panels_are_rendered(self):
        panel_body=self.app.split('key(sheet,s.sheetId){when(sheet)',1)[1].split('@Composable private fun Panel',1)[0]
        self.assertEqual(set(re.findall(r'Sheet\.(\w+)->',panel_body)),{'PROFILE','PIN','HELP','ALLOCATE','ENROLL','STAFF','STAFF_EDIT','REMOVE_STAFF','GATEWAY','RAW','MEMBER_DETAILS','HISTORY','AUDIT','FILTERS'})
    def test_reduced_motion_does_not_keep_outgoing_records(self):
        self.assertIn('progress.snapTo(1f)',self.behavior);self.assertIn('tween(160)',self.behavior)
        self.assertNotIn('Crossfade(',self.behavior);self.assertNotIn('AnimatedContent(',self.behavior)
    def test_ime_chains_and_secret_disposal_are_explicit(self):
        self.assertIn('nextFocus.requestFocus()',self.app);self.assertIn('Key.NumPadEnter',self.app)
        self.assertIn('if(imeVisible){keyboard?.hide();focus.clearFocus()}',self.app)
        self.assertIn('pin=""',self.app);self.assertIn('current="";next="";confirm=""',self.app)
    def test_signin_has_no_undefined_pending_variable(self):
        login=self.app.split('private fun Login(',1)[1].split('@OptIn',1)[0]
        self.assertNotIn('pending',login)
    def test_modal_dirty_dismissal_is_vetoed(self):
        self.assertIn('confirmValueChange={target->',self.app)
        self.assertIn('latest.value.busy||latest.value.draftDirty',self.app)
        self.assertIn('rememberLazyListState(position.first,position.second)',self.app)
    def test_small_text_and_amount_floor(self):
        self.assertTrue(all(int(n)>=14 for n in re.findall(r'fontSize=(\d+)\.sp',self.app)))
        self.assertIn('Presentation.MONEY_MIN_SP',self.app);self.assertIn('fontFeatureSettings="tnum"',self.app)
        self.assertGreaterEqual(self.app.count('maxWidth<360.dp||fontScale>=1.5f'),3)
    def test_token_contrast_on_bounded_washes_and_glass(self):
        for name,ratio in contrast_evidence().items():self.assertGreaterEqual(ratio,4.5,f'{name}: {ratio}')
    def test_twelve_controller_journeys_have_distinct_ids(self):
        source=(NATIVE/'viewmodel-tests/JourneyChecks.kt').read_text()
        self.assertEqual(re.findall(r'journey\("(J\d+)"',source),[f'J{i:02}' for i in range(1,13)])
    def test_instrumentation_is_not_in_shipping_source(self):
        for p in (NATIVE/'app/src/main').rglob('*.kt'):self.assertNotIn('FakeController',p.read_text())
if __name__=='__main__':unittest.main()
