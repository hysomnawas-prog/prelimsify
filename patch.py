from pathlib import Path
p=Path('/mnt/data/prelimsify_work/js/app.js')
s=p.read_text()
s=s.replace("let supabaseUser = null;", "let supabaseUser = null;\nlet currentProfile = null;\nlet currentTestTitle = 'Prelimsify Test';")
s=s.replace("async function showTest(){\n  historySavedForSubmission = false;", "async function showTest(){\n  if (!requireSignedIn()) return;\n  historySavedForSubmission = false;")
s=s.replace("function showHome(){\n  setTestPaletteVisibility(false);", "function showHome(){\n  setTestPaletteVisibility(false);")
# Replace score history render/load block
start=s.index('function renderScoreHistory(rows, note=\'\'){')
end=s.index('\nfunction projectPreview', start)
new=r'''function renderScoreHistory(rows, note=''){
  const list=document.getElementById('scoreHistoryList');
  const count=document.getElementById('scoreHistoryCount');
  const status=document.getElementById('scoreHistoryStatus');
  const boardCount=document.getElementById('scoreBoardCount');
  if(!list||!count)return;
  rows=Array.isArray(rows)?rows:[];
  count.textContent=`${rows.length} ${rows.length===1?'test':'tests'}`;
  if(status) status.textContent=note;
  if(boardCount) boardCount.textContent=`${rows.length} ${rows.length===1?'test':'tests'}`;
  if(!rows.length){
    list.innerHTML='<div class="history-empty">No completed tests yet.</div>';
    return;
  }
  list.innerHTML=rows.map(r=>{
    const d=r.completed_at?new Date(r.completed_at).toLocaleString([], {day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}):'—';
    const pass=r.passed?'PASS':'FAIL';
    return `<div class="history-row">
      <div><div class="history-title">${escapeHistory(r.username||'User')} · ${escapeHistory(r.title||'Test')}</div><div class="history-date">${escapeHistory(d)}</div></div>
      <div class="history-score">${Number(r.marks||0).toFixed(2)}<span> / ${Number(r.max_marks||0).toFixed(2)}</span></div>
      <div class="history-percent">${Number(r.percentage||0).toFixed(1)}%</div>
      <div class="history-breakdown">✓ ${Number(r.correct||0)} &nbsp; ✕ ${Number(r.wrong||0)} &nbsp; — ${Number(r.unanswered||0)}</div>
      <div class="history-result ${r.passed?'history-pass':'history-fail'}">${pass}</div>
    </div>`;
  }).join('');
}
function escapeHistory(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
async function loadScoreHistory(){
  if(!supabaseClient||!supabaseUser){
    renderScoreHistory([], 'Sign in to view the shared scoreboard.');
    return;
  }
  try{
    const {data,error}=await supabaseClient.from('scoreboard_entries')
      .select('id,username,title,marks,max_marks,percentage,passed,correct,wrong,unanswered,completed_at')
      .order('completed_at',{ascending:false}).limit(200);
    if(error)throw error;
    renderScoreHistory(data||[],'Shared scoreboard');
  }catch(e){
    console.warn('Scoreboard could not be loaded:',e);
    renderScoreHistory([], 'Scoreboard is temporarily unavailable.');
  }
}
async function saveScoreHistory(){
  if(historySavedForSubmission)return;
  historySavedForSubmission=true;
  if(!supabaseClient||!supabaseUser)return;
  const maxMarks=total*MARK_CORRECT;
  const percentage=maxMarks?(marks/maxMarks)*100:0;
  const passMark=maxMarks*(PASS_PERCENT/100);
  const row={
    title:(currentTestTitle||'Prelimsify Test').trim()||'Prelimsify Test',
    marks:Number(marks.toFixed(2)),max_marks:Number(maxMarks.toFixed(2)),percentage:Number(percentage.toFixed(2)),
    passed:marks>=passMark,correct:correctCount,wrong:wrongCount,unanswered:Math.max(0,total-answered),completed_at:new Date().toISOString()
  };
  try{
    const {error}=await supabaseClient.from(TEST_HISTORY_TABLE).insert({...row,user_id:supabaseUser.id});
    if(error)throw error;
    await loadScoreHistory();
  }catch(e){
    console.warn('Score history could not be saved to Supabase:',e);
  }
}
'''
s=s[:start]+new+s[end:]
# applyProjectPaper sets title
needle="  currentData = questions;\n  MARK_CORRECT = Number(payload.markCorrect ?? 2);"
s=s.replace(needle, "  currentData = questions;\n  currentTestTitle = String(payload.title || 'Question Set').trim() || 'Question Set';\n  const titleEl = document.getElementById('titleText');\n  if (titleEl) titleEl.textContent = currentTestTitle;\n  MARK_CORRECT = Number(payload.markCorrect ?? 2);")
# loadQuestionSet set title to current generic
s=s.replace("  currentData = parsed;\n  buildQuiz();", "  currentData = parsed;\n  currentTestTitle = 'Question Set';\n  const titleEl = document.getElementById('titleText');\n  if (titleEl) titleEl.textContent = currentTestTitle;\n  buildQuiz();")
# save current name updates active title
s=s.replace("  const projectPaper = makeProjectPaper();\n  projectPaper.title = cleanName;", "  const projectPaper = makeProjectPaper();\n  projectPaper.title = cleanName;\n  currentTestTitle = cleanName;\n  const titleEl = document.getElementById('titleText');\n  if (titleEl) titleEl.textContent = currentTestTitle;")
# initSupabase remove anonymous block
old="""    if (sessionData && sessionData.session){\n      supabaseUser = sessionData.session.user;\n      return true;\n    }\n\n    const { data, error } = await supabaseClient.auth.signInAnonymously();\n    if (error) throw error;\n\n    supabaseUser = data.user;\n    return !!supabaseUser;"""
newauth="""    if (sessionData && sessionData.session){\n      supabaseUser = sessionData.session.user;\n      return await loadCurrentProfile();\n    }\n    return false;"""
s=s.replace(old,newauth)
# Insert auth helper before initSupabase
marker='async function initSupabase(){'
auth=r'''
function usernameEmail(username){
  return `${String(username).trim().toLowerCase()}@users.prelimsify.local`;
}
function cleanUsername(v){
  return String(v||'').trim().toLowerCase().replace(/[^a-z0-9_.-]/g,'').slice(0,32);
}
function requireSignedIn(){
  if(supabaseUser) return true;
  openAuthModal('login');
  return false;
}
async function loadCurrentProfile(){
  if(!supabaseClient||!supabaseUser)return false;
  const {data,error}=await supabaseClient.from('profiles').select('id,username,display_name,role,can_use_app').eq('id',supabaseUser.id).single();
  if(error){ console.warn('Profile load failed:',error); return false; }
  currentProfile=data;
  if(data.can_use_app === false && data.role !== 'admin'){
    await supabaseClient.auth.signOut();
    supabaseUser=null; currentProfile=null;
    setAuthStatus('Your account is currently disabled by an administrator.', false);
    return false;
  }
  updateAuthUI();
  return true;
}
async function signInWithUsername(username,password){
  username=cleanUsername(username);
  if(username.length<3) throw new Error('Username must be at least 3 characters.');
  const {data,error}=await supabaseClient.auth.signInWithPassword({email:usernameEmail(username),password});
  if(error)throw error;
  supabaseUser=data.user;
  if(!(await loadCurrentProfile())) throw new Error('Your account is not permitted to use Prelimsify.');
  closeAuthModal();
  return true;
}
async function createUsernameAccount(username,password){
  username=cleanUsername(username);
  if(username.length<3) throw new Error('Username must be at least 3 characters.');
  if(!/^[a-z0-9_.-]+$/.test(username)) throw new Error('Username may contain letters, numbers, dot, underscore and hyphen only.');
  if(!password || password.length<6) throw new Error('Password must be at least 6 characters.');
  const {data,error}=await supabaseClient.auth.signUp({email:usernameEmail(username),password,options:{data:{username,display_name:username}}});
  if(error)throw error;
  if(!data.session){ throw new Error('Account created. Ask the administrator to disable email confirmation in Supabase, then log in with your username and password.'); }
  supabaseUser=data.user;
  await loadCurrentProfile();
  closeAuthModal();
  return true;
}
async function renameCurrentUsername(newUsername){
  if(!requireSignedIn())return;
  newUsername=cleanUsername(newUsername);
  if(newUsername.length<3) throw new Error('Username must be at least 3 characters.');
  if(newUsername === String(currentProfile?.username||'').toLowerCase()) return;
  const {data,error}=await supabaseClient.auth.updateUser({email:usernameEmail(newUsername),data:{username:newUsername,display_name:newUsername}});
  if(error)throw error;
  const {error:profileError}=await supabaseClient.from('profiles').update({username:newUsername,display_name:newUsername}).eq('id',supabaseUser.id);
  if(profileError)throw profileError;
  currentProfile={...currentProfile,username:newUsername,display_name:newUsername};
  updateAuthUI();
  return data;
}
async function logoutCurrentUser(){
  if(supabaseClient) await supabaseClient.auth.signOut();
  supabaseUser=null; currentProfile=null;
  updateAuthUI();
  showHome();
}
function setAuthStatus(msg,ok){
  const el=document.getElementById('authStatus');
  if(el){el.textContent=msg||'';el.className='auth-status '+(ok?'ok':'error');}
}
function updateAuthUI(){
  const panel=document.getElementById('accountPanel');
  const label=document.getElementById('accountName');
  const adminLink=document.getElementById('adminBranchLink');
  if(!panel)return;
  if(supabaseUser&&currentProfile){
    panel.classList.add('signed-in');
    label.textContent=currentProfile.username||currentProfile.display_name||'User';
    adminLink.style.display=currentProfile.role==='admin'?'inline-flex':'none';
  }else{
    panel.classList.remove('signed-in');
    label.textContent='Not signed in';
    adminLink.style.display='none';
  }
}
function openAuthModal(mode='login'){
  const modal=document.getElementById('authOverlay'); if(!modal)return;
  modal.classList.add('open'); modal.setAttribute('aria-hidden','false');
  document.getElementById('authMode').value=mode;
  document.getElementById('authUsername').value=''; document.getElementById('authPassword').value='';
  document.getElementById('authConfirmPassword').value='';
  document.getElementById('authConfirmPassword').style.display=mode==='signup'?'block':'none';
  document.getElementById('authSubmitBtn').textContent=mode==='signup'?'Create Account':'Login';
  document.getElementById('authSwitchText').textContent=mode==='signup'?'Already have an account?':'New user?';
  document.getElementById('authSwitchBtn').textContent=mode==='signup'?'Login':'Create account';
  setAuthStatus('',true);
}
function closeAuthModal(){const m=document.getElementById('authOverlay');if(m){m.classList.remove('open');m.setAttribute('aria-hidden','true');}}
function setupAuthUI(){
  const login=document.getElementById('loginBtn'), signup=document.getElementById('signupBtn');
  login?.addEventListener('click',()=>openAuthModal('login')); signup?.addEventListener('click',()=>openAuthModal('signup'));
  document.getElementById('logoutBtn')?.addEventListener('click',logoutCurrentUser);
  document.getElementById('renameUserBtn')?.addEventListener('click',async()=>{
    const next=prompt('New username:',currentProfile?.username||''); if(next===null)return;
    try{await renameCurrentUsername(next);setAuthStatus('Username renamed successfully.',true);}catch(e){setAuthStatus(e.message||String(e),false);}
  });
  document.getElementById('authCloseBtn')?.addEventListener('click',closeAuthModal);
  document.getElementById('authSwitchBtn')?.addEventListener('click',()=>openAuthModal(document.getElementById('authMode').value==='login'?'signup':'login'));
  document.getElementById('authForm')?.addEventListener('submit',async e=>{
    e.preventDefault();
    const mode=document.getElementById('authMode').value, u=document.getElementById('authUsername').value, p=document.getElementById('authPassword').value, c=document.getElementById('authConfirmPassword').value;
    try{
      setAuthStatus('Working…',true);
      if(mode==='signup'){ if(p!==c)throw new Error('Passwords do not match.'); await createUsernameAccount(u,p); setAuthStatus('Account created.',true); }
      else await signInWithUsername(u,p);
    }catch(err){setAuthStatus(err.message||String(err),false);}
  });
  document.getElementById('authOverlay')?.addEventListener('click',e=>{if(e.target.id==='authOverlay')closeAuthModal();});
  updateAuthUI();
}

'''
s=s.replace(marker,auth+marker)
# Add auth setup before init
s=s.replace('// init\n(async function init(){', "setupAuthUI();\n\n// init\n(async function init(){")
# session event listener after initSupabase? append before setup call, but setup after function definitions and before init; add listener there
s=s.replace("setupAuthUI();\n\n// init", "if (window.supabase) {\n  // Keep UI/profile in sync after login/logout in another tab.\n  // The client is initialized just below, so this callback is attached after init as well.\n}\nsetupAuthUI();\n\n// init")
# Modify init after connected
s=s.replace("  if (connected) {\n    await moveBuiltInPaperToSavedProjects();\n  }", "  if (connected) {\n    await moveBuiltInPaperToSavedProjects();\n  }\n  if (supabaseClient) {\n    supabaseClient.auth.onAuthStateChange(async (_event, session) => {\n      supabaseUser = session?.user || null;\n      if (supabaseUser) await loadCurrentProfile(); else { currentProfile=null; updateAuthUI(); }\n    });\n  }")
p.write_text(s)
