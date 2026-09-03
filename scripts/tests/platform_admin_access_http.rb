# Isolated PostgREST contract, synthetic sessions/tokens only. No OTP/provider calls.
require 'json'
require 'open3'
require 'uri'
require 'net/http'
require 'openssl'
require 'base64'
require 'time'
DB = 'collect_platform_access_uat_20260902'.freeze
CONTAINER = 'collect_platform_access_api_20260902'.freeze
IDS = (1..3).map { |n| "98500000-0000-4000-8000-#{n.to_s.rjust(12,'0')}" }.freeze
SECRET = 'isolated-platform-access-uat-only-20260902-not-production'.freeze
def run(*args, input: '', env: {})
  out, err, status = Open3.capture3(env,*args,stdin_data:input)
  raise err.gsub(/postgres(?:ql)?:\/\/\S+/, '[LOCAL_DB_URI]') unless status.success?
  out
end
def sql(input)
  run('docker','exec','-i','supabase_db_collect','psql','-XqAt','-U','postgres','-d',DB,'-v','ON_ERROR_STOP=1',input:input)
end
def token(n, session: true)
  encode = ->(value) { Base64.urlsafe_encode64(JSON.generate(value),padding:false) }
  claims = {sub:IDS[n-1],role:'authenticated',aud:'authenticated',exp:Time.now.to_i+600,
    user_metadata:{role:'platform_owner',is_platform_admin:true}}
  claims[:session_id] = "98510000-0000-4000-8000-#{n.to_s.rjust(12,'0')}" if session
  unsigned = encode.call(alg:'HS256',typ:'JWT')+'.'+encode.call(claims)
  unsigned+'.'+Base64.urlsafe_encode64(OpenSSL::HMAC.digest('SHA256',SECRET,unsigned),padding:false)
end
def request(path, body: nil, jwt: nil, profile: nil)
  uri = URI('http://127.0.0.1:55440'+path)
  req = body ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  req['Content-Type']='application/json'
  req['Authorization']='Bearer '+jwt if jwt
  req['Accept-Profile']=profile if profile
  req.body=JSON.generate(body) if body
  response = Net::HTTP.start(uri.host,uri.port,open_timeout:2,read_timeout:10){|http|http.request(req)}
  [response.code.to_i,response.body.empty? ? nil : JSON.parse(response.body)]
end
def rpc(name,params=nil,as:1,jwt:nil,**named_params)
  request('/rpc/'+name,body:params || named_params,jwt:jwt || (as && token(as)))
end
checks=[]
check = lambda do |name, condition, code=nil|
  checks << {name:name,status:condition ? 'pass' : 'fail',http_status:code}
  raise "FAIL #{name} (HTTP #{code})" unless condition
end
inspect = JSON.parse(run('docker','inspect','supabase_rest_collect')).first
settings = inspect.fetch('Config').fetch('Env').to_h { |entry| entry.split('=',2) }
db_uri = URI(settings.fetch('PGRST_DB_URI'))
raise 'Unexpected host' unless db_uri.host=='supabase_db_collect'
db_uri.path='/'+DB
bridge=inspect.fetch('NetworkSettings').fetch('Networks').keys.find{|name|name.include?('collect')}
raise 'Collect network missing' unless bridge
existing,_,present=Open3.capture3('docker','inspect',CONTAINER)
if present.success?
  active=JSON.parse(existing).first
  raise 'Unexpected existing API target' unless active.fetch('Config').fetch('Env').include?('PGRST_DB_URI='+db_uri.to_s)
  raise 'Unexpected test JWT config' unless active.fetch('Config').fetch('Env').include?('PGRST_JWT_SECRET='+SECRET)
else
  run('docker','run','--detach','--rm','--name',CONTAINER,'--network',bridge,
    '--publish','127.0.0.1:55440:3000','--env','PGRST_DB_URI','--env','PGRST_JWT_SECRET',
    '--env','PGRST_DB_ANON_ROLE=anon','--env','PGRST_DB_SCHEMAS=public','--env','PGRST_DB_EXTRA_SEARCH_PATH=public,extensions',
    inspect.fetch('Config').fetch('Image'),env:{'PGRST_DB_URI'=>db_uri.to_s,'PGRST_JWT_SECRET'=>SECRET})
end
created=false
begin
  raise 'Wrong database' unless sql('select current_database();').strip==DB
  raise 'Fixture namespace occupied' unless sql("select not exists(select 1 from auth.users where id in ('#{IDS.join("','")}'));").strip=='t'
  sql(<<~SQL)
    begin;
    insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
    select ('98500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
      '25078898500'||n,now(),'{}','{}' from generate_series(1,3)n;
    update public.profiles set public_id='98500'||right(id::text,1) where id in ('#{IDS.join("','")}');
    insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason)
    values('#{IDS[0]}','+250788985001','Synthetic initial approved operator');
    insert into public.admin_user_roles(user_id,role_id,reason)
    select '#{IDS[0]}',id,'Synthetic initial role' from public.admin_roles where name='platform_owner';
    insert into auth.sessions(id,user_id,created_at)
    select ('98510000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
      ('98500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,clock_timestamp() from generate_series(1,3)n;
    commit; notify pgrst,'reload schema';
  SQL
  created=true
  20.times do
    begin
      code,_=rpc('admin_get_whatsapp_approval',{p_user_id:IDS[1]})
      break unless code==404
    rescue Errno::ECONNREFUSED,EOFError
    end
    sleep 0.2
  end
  code,data=rpc('admin_current_user')
  check.call('approved live synthetic session reaches Admin',code==200 && data['user_id']==IDS[0],code)
  code,data=rpc('admin_list_admin_users',{p_search:'985001',p_status:'active'})
  check.call('two-argument Admin list resolves without overload ambiguity',code==200 && data['total']==1,code)
  code,data=rpc('admin_current_user',as:3)
  check.call('ordinary member with forged metadata denied Admin',code==200 && data=={},code)
  code,data=rpc('admin_current_user',jwt:token(1,session:false))
  check.call('approved operator without session ID denied',code==200 && data=={},code)
  code,data=rpc('admin_get_whatsapp_approval',{p_user_id:IDS[1]})
  check.call('approval status masked and unapproved',code==200 && data['approved']==false && data['role_granted']==false && data['phone_masked']=='+***5002',code)
  %w[admin_approve_whatsapp admin_revoke_whatsapp_approval admin_set_user_access].each do |name|
    params={p_user_id:IDS[1],p_reason:'Synthetic denied request'}
    params[:p_whatsapp_phone]='+250788985002' if name=='admin_approve_whatsapp'
    params[:p_active]=true if name=='admin_set_user_access'
    [nil,3].each do |actor|
      code,_=rpc(name,params,as:actor)
      check.call("#{actor ? 'member' : 'anonymous'} denied #{name}",[400,401,403,404].include?(code),code)
    end
  end
  code,_=rpc('admin_bootstrap_whatsapp_approval',{p_user_id:IDS[1],p_whatsapp_phone:'+250788985002',p_reason:'Browser bootstrap'})
  check.call('even approved browser operator cannot bootstrap',[401,403,404].include?(code),code)
  code,_=request('/whatsapp_approvals?select=*',jwt:token(1))
  check.call('private approval table not exposed',code==404,code)
  code,_=request('/whatsapp_approvals?select=*',jwt:token(1),profile:'collect_admin_access')
  check.call('private schema cannot be selected by API profile',code==406,code)
  code,_=rpc('verified_phone',{p_user:IDS[1]})
  check.call('private Auth identity helper not exposed',code==404,code)
  code,_=rpc('admin_set_user_access',{p_user_id:IDS[1],p_active:true,p_reason:'No approval'})
  check.call('activation before approval rejected',code==403,code)
  approval={p_user_id:IDS[1],p_whatsapp_phone:'+250788985002',p_reason:'Synthetic reviewed WhatsApp'}
  code,data=rpc('admin_approve_whatsapp',approval)
  check.call('exact approval receipt',code==200 && data=={'ok'=>true,'status'=>'approved','user_id'=>IDS[1]},code)
  code,data=rpc('admin_list_admin_users',{p_search:'985002',p_status:'approved',p_limit:25,p_offset:0,p_sort:'created_at_desc'})
  check.call('approved account appears awaiting activation',code==200 && data['total']==1 && data['rows'].first['status']=='approved',code)
  access={p_user_id:IDS[1],p_active:true,p_reason:'Synthetic reviewed activation'}
  code,data=rpc('admin_set_user_access',access)
  check.call('exact activation receipt',code==200 && data=={'ok'=>true,'status'=>'active'},code)
  stale_token=token(2)
  code,data=rpc('admin_current_user',jwt:stale_token)
  check.call('preapproval session stays denied after activation',code==200 && data=={},code)
  sql("update auth.sessions set created_at=clock_timestamp() where user_id='#{IDS[1]}';")
  code,data=rpc('admin_current_user',as:2)
  check.call('synthetic new sign-in reaches Admin after approval and grant',code==200 && data['user_id']==IDS[1],code)
  code,data=rpc('admin_revoke_whatsapp_approval',{p_user_id:IDS[1],p_reason:'Synthetic revoke'})
  check.call('revocation confirmed',code==200 && data=={'ok'=>true,'status'=>'revoked','user_id'=>IDS[1]},code)
  code,data=rpc('admin_current_user',jwt:stale_token)
  check.call('same unexpired JWT denied after revocation',code==200 && data=={},code)
  code,_=rpc('admin_get_admin_user',{p_id:IDS[0]},jwt:stale_token)
  check.call('revoked JWT cannot inspect Admin accounts',[400,403].include?(code),code)
  code,_=rpc('admin_approve_whatsapp',{p_user_id:IDS[2],p_whatsapp_phone:'+250788985003',p_reason:'Revoked operator'},jwt:stale_token)
  check.call('revoked JWT cannot approve another number',[400,403].include?(code),code)
  code,data=rpc('admin_get_admin_user',{p_id:IDS[1]})
  check.call('revoked detail does not display active',code==200 && data['admin_access']==false && data['active_roles']==[],code)
  %w[admin_grant_user_role admin_revoke_user_role].each do |name|
    code,_=rpc(name,{p_user_id:IDS[2],p_role_name:'platform_owner',p_reason:'Legacy bypass'})
    check.call('legacy mutation denied '+name,[401,403,404].include?(code),code)
  end
ensure
  if created
    sql(<<~SQL)
      begin;
      delete from public.audit_logs where entity_id in ('#{IDS.join("','")}');
      delete from auth.users where id in ('#{IDS.join("','")}') and phone in ('250788985001','250788985002','250788985003');
      commit;
    SQL
    check.call('exact synthetic HTTP fixture cleanup',sql("select not exists(select 1 from auth.users where id in ('#{IDS.join("','")}'));").strip=='t')
  end
end
puts JSON.pretty_generate(captured_at:Time.now.utc.iso8601,database:DB,api:'127.0.0.1:55440',mode:'synthetic local PostgREST, not real OTP or hosted UAT',checks:checks)
