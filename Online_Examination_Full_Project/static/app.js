const $ = (id) => document.getElementById(id);
let currentStudent = null;
let activeExamId = null;

async function api(url, options={}) {
  const response = await fetch(url, {headers:{"Content-Type":"application/json"}, ...options});
  const data = await response.json().catch(()=>({error:"Unexpected server response."}));
  if (!response.ok) throw new Error(data.error || "Request failed.");
  return data;
}
function toast(message) {
  const el=$("toast"); el.textContent=message; el.classList.add("show");
  clearTimeout(window.toastTimer); window.toastTimer=setTimeout(()=>el.classList.remove("show"),3200);
}
function esc(value) { return String(value ?? "").replace(/[&<>"']/g, c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])); }
function showPage(name) {
  ["overview","exams","results","analytics"].forEach(p=>$(p+"Page").hidden=(p!==name));
  $("examPanel").hidden=true;
  document.querySelectorAll(".nav-item").forEach(b=>b.classList.toggle("active",b.dataset.page===name));
  $("pageTitle").textContent={overview:"Overview",exams:"Examinations",results:"My Results",analytics:"Analytics"}[name];
  if(name==="exams") loadExams();
  if(name==="results") loadResults();
  if(name==="analytics") loadAnalytics();
}
function examCard(e) {
  const registered=e.registration_status==="REGISTERED"||e.registration_status==="COMPLETED";
  const completed=e.registration_status==="COMPLETED";
  let action=registered ? (completed?`<button class="secondary" disabled>Completed</button>`:`<button class="primary" onclick="startExam(${e.exam_id})">Start exam →</button>`)
    : `<button class="primary" onclick="registerExam(${e.exam_id})">Register →</button>`;
  return `<article class="exam-card"><div class="card-top"><span class="tag">${esc(e.exam_type)}</span><span class="status">${esc(e.exam_status)}</span></div><h4>${esc(e.exam_title)}</h4><div class="subject">${esc(e.subject_code)} · ${esc(e.subject_name)}</div><div class="exam-facts"><span>◷ ${esc(e.start_time)}</span><span>◴ ${e.duration_minutes} min</span><span>▤ ${e.question_count ?? "—"} questions</span><span>◎ ${e.total_marks} marks</span></div><div class="exam-card-foot"><small>${registered?(completed?"Submission recorded":"You are registered"):"Registration required"}</small>${action}</div></article>`;
}
async function loadDashboard() {
  const d=await api("/api/dashboard");
  $("statStudents").textContent=d.stats.students;
  $("statExams").textContent=d.stats.exams;
  $("statQuestions").textContent=d.stats.questions;
  $("statResults").textContent=d.stats.results;
  $("recentExams").innerHTML=d.exams.slice(0,4).map(examCard).join("")||'<div class="empty">No examinations found in the database.</div>';
}
async function loadExams() {
  const d=await api("/api/exams");
  $("allExams").innerHTML=d.exams.map(examCard).join("")||'<div class="empty">No examinations found.</div>';
}
async function registerExam(id) {
  try { const d=await api(`/api/exams/${id}/register`,{method:"POST",body:"{}"}); toast(d.message); loadExams(); loadDashboard(); }
  catch(e){toast(e.message);}
}
async function startExam(id) {
  try {
    const d=await api(`/api/exams/${id}/questions`);
    activeExamId=id;
    $("portal").hidden=true; $("examPanel").hidden=false;
    $("examTitle").textContent=d.exam.exam_title;
    $("examMeta").textContent=`${d.questions.length} questions · ${d.exam.total_marks} total marks`;
    $("examDuration").textContent=`${d.exam.duration_minutes} min`;
    $("questionList").innerHTML=d.questions.map((q,i)=>`<article class="question-card"><div class="question-head"><span>QUESTION ${i+1} OF ${d.questions.length}</span><span>${q.marks} MARKS · ${esc(q.difficulty)}</span></div><h4>${esc(q.question_text)}</h4>${q.options.map(o=>`<label class="option"><input type="radio" name="q_${q.question_id}" value="${o.option_id}"><b>${esc(o.option_label)}.</b> ${esc(o.option_text)}</label>`).join("")}</article>`).join("")||'<div class="empty">No questions are assigned to this exam.</div>';
    document.querySelectorAll('#questionList input').forEach(x=>x.addEventListener("change",updateAnswered));
    updateAnswered();
    $("pageTitle").textContent="Examination attempt";
    window.scrollTo({top:0,behavior:"smooth"});
  } catch(e){toast(e.message);}
}
function updateAnswered() {
  const count=new Set([...document.querySelectorAll('#questionList input:checked')].map(x=>x.name)).size;
  const total=new Set([...document.querySelectorAll('#questionList input')].map(x=>x.name)).size;
  $("answeredCount").textContent=`${count} of ${total} answers selected`;
}
async function loadResults() {
  try {
    const d=await api("/api/results");
    $("resultsList").innerHTML=d.results.length?`<table class="data-table"><thead><tr><th>Examination</th><th>Subject</th><th>Score</th><th>Percentage</th><th>Status</th><th>Evaluated</th></tr></thead><tbody>${d.results.map(r=>`<tr><td><b>${esc(r.exam_title)}</b></td><td>${esc(r.subject_name)}</td><td>${r.marks_obtained} / ${r.total_marks}</td><td>${r.percentage}%</td><td><span class="result-pill ${r.result_status==="PASS"?"pill-pass":"pill-fail"}">${r.result_status}</span></td><td>${esc(r.evaluated_at)}</td></tr>`).join("")}</tbody></table>`:'<div class="empty">No results yet. Complete a registered examination to see your score here.</div>';
  } catch(e){toast(e.message);}
}
async function loadAnalytics() {
  try {
    const d=await api("/api/admin/analytics");
    const subjects=d.subjects.map(s=>`<tr><td>${esc(s.subject_name)}</td><td>${esc(s.exam_title)}</td><td>${s.students_evaluated}</td><td>${s.average_percentage??"—"}%</td><td>${s.pass_count??0}</td><td>${s.fail_count??0}</td></tr>`).join("");
    const ranks=d.rankings.map(r=>`<tr><td>${esc(r.exam_title)}</td><td>${esc(r.student_name)}</td><td>${r.marks_obtained}/${r.total_marks}</td><td>${r.percentage}%</td><td>#${r.exam_rank}</td></tr>`).join("");
    $("analyticsContent").innerHTML=`<div class="analytics-grid"><div class="analytics-card"><h4>Subject performance</h4><table class="data-table"><thead><tr><th>Subject</th><th>Exam</th><th>Students</th><th>Average</th><th>Pass</th><th>Fail</th></tr></thead><tbody>${subjects||'<tr><td colspan="6">No analytics yet.</td></tr>'}</tbody></table></div><div class="analytics-card"><h4>Examination rankings</h4><table class="data-table"><thead><tr><th>Exam</th><th>Student</th><th>Score</th><th>Percent</th><th>Rank</th></tr></thead><tbody>${ranks||'<tr><td colspan="5">No rankings yet.</td></tr>'}</tbody></table></div></div>`;
  } catch(e){$("analyticsContent").innerHTML=`<div class="empty">${esc(e.message)}<br><br>Ranking analytics require MySQL 8.0+.</div>`;}
}
$("loginForm").addEventListener("submit",async e=>{
  e.preventDefault(); $("loginMessage").textContent="Signing in…";
  try {
    const d=await api("/api/login",{method:"POST",body:JSON.stringify({enrollment_no:$("enrollment").value,email:$("email").value})});
    currentStudent=d.student; enterPortal(d.student); toast("Welcome, "+d.student.name);
  } catch(err){$("loginMessage").textContent=err.message;}
});
function enterPortal(student) {
  $("loginPanel").hidden=true; $("portal").hidden=false;
  $("sideName").textContent=student.name; $("sideEnrollment").textContent=student.enrollment_no;
  $("welcomeName").textContent=student.name.split(" ")[0]; $("profileChip").textContent=student.enrollment_no;
  $("logoutBtn").hidden=false;
  $("todayDate").textContent=new Date().toLocaleDateString(undefined,{weekday:"short",day:"numeric",month:"short",year:"numeric"});
  showPage("overview"); loadDashboard();
}
document.querySelectorAll(".nav-item").forEach(b=>b.addEventListener("click",()=>showPage(b.dataset.page)));
document.querySelectorAll("[data-goto]").forEach(b=>b.addEventListener("click",()=>showPage(b.dataset.goto)));
$("refreshResults").addEventListener("click",loadResults);
$("logoutBtn").addEventListener("click",async()=>{await api("/api/logout",{method:"POST",body:"{}"});currentStudent=null;$("portal").hidden=true;$("loginPanel").hidden=false;$("logoutBtn").hidden=true;$("sideName").textContent="Guest student";$("sideEnrollment").textContent="Sign in to continue";$("profileChip").textContent="Guest";showPage("overview");});
$("backToExams").addEventListener("click",()=>{ $("examPanel").hidden=true;$("portal").hidden=false;showPage("exams");});
$("attemptForm").addEventListener("submit",async e=>{
  e.preventDefault();
  if(!activeExamId)return;
  const answers={};
  document.querySelectorAll('#questionList input:checked').forEach(input=>{answers[input.name.replace("q_","")]=Number(input.value);});
  if(!confirm(`Submit this examination with ${Object.keys(answers).length} answers selected? Unanswered questions will receive zero marks.`))return;
  try {
    const d=await api(`/api/exams/${activeExamId}/submit`,{method:"POST",body:JSON.stringify({answers})});
    $("examPanel").hidden=true;$("portal").hidden=false;showPage("results");
    toast(`Submitted. Score: ${d.result.marks_obtained}/${d.result.total_marks} (${d.result.percentage}%) · ${d.result.result_status}`);
    loadDashboard();
  } catch(err){toast(err.message);}
});
(async()=>{
  try {
    const d=await api("/api/me");
    if(d.student) enterPortal(d.student);
    else {
      $("todayDate").textContent=new Date().toLocaleDateString(undefined,{weekday:"short",day:"numeric",month:"short",year:"numeric"});
    }
  } catch(e){$("loginMessage").textContent="Start the Flask server and verify the database configuration.";}
})();
