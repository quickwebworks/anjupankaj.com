<?php
declare(strict_types=1);
// Install alongside the year folders at media.anjupankaj.com, not on Vercel.
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
$origins = ['https://anjupankaj.com', 'https://www.anjupankaj.com', 'https://anjupankaj-news-portal.loyal-earth-4429.chatgpt.site'];
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
function fail_upload(int $status, string $message): never {
 http_response_code($status); echo json_encode(['error'=>$message]); exit;
}
if (!in_array($origin, $origins, true)) fail_upload(403, 'Website origin is not allowed.');
header('Access-Control-Allow-Origin: '.$origin);
header('Vary: Origin');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {http_response_code(204);exit;}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') fail_upload(405, 'Use POST.');
if ((int)($_SERVER['CONTENT_LENGTH'] ?? 0) > 6*1024*1024) fail_upload(413, 'Maximum image size is 5 MB.');
$authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
if (!preg_match('/^Bearer ([A-Za-z0-9._-]+)$/D', $authorization, $matches)) fail_upload(401, 'Sign in first.');
$configFile=__DIR__.'/cms-config.php';
if(!is_file($configFile)) fail_upload(503,'AnjuPankaj media setup is pending.');
$config=require $configFile;
$base=rtrim($config['url'] ?? '', '/');
$key=$config['publishable_key'] ?? '';
if (!preg_match('#^https://[a-z0-9]+\.supabase\.co$#D',$base) || !$key) fail_upload(503,'AnjuPankaj media server database setup is pending.');
function db_get(string $path): array {
 global $base,$key,$authorization;
 $ch=curl_init($base.$path);
 curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>5,CURLOPT_TIMEOUT=>15,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_HTTPHEADER=>['apikey: '.$key,'Authorization: '.$authorization]]);
 $body=curl_exec($ch);$status=curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);
 if ($status!==200 || $body===false) fail_upload($status===401?401:503,'Cannot verify publication access.');
 $result=json_decode($body,true);if(!is_array($result)) fail_upload(503,'Invalid authentication response.');return $result;
}
// Verify the token with Auth, then check authoritative, RLS-protected membership.
$user=db_get('/auth/v1/user');$uid=$user['id']??'';
if (!preg_match('/^[0-9a-f-]{36}$/iD',$uid)) fail_upload(401,'Invalid session.');
$admin=db_get('/rest/v1/cms_admins?select=user_id&user_id=eq.'.rawurlencode($uid));
$editor=$admin?[]:db_get('/rest/v1/cms_editors?select=user_id&user_id=eq.'.rawurlencode($uid));
if (!$admin && !$editor) fail_upload(403,'Publication editor access required.');
$file=$_FILES['image']??null;
if (!$file || $file['error']!==UPLOAD_ERR_OK || !is_uploaded_file($file['tmp_name'])) fail_upload(400,'Choose an image up to 5 MB.');
$size=filesize($file['tmp_name']);if(!$size || $size>5*1024*1024) fail_upload(413,'Maximum image size is 5 MB.');
$mime=(new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
$extensions=['image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp','image/gif'=>'gif'];
$dimensions=@getimagesize($file['tmp_name']);
if(!isset($extensions[$mime]) || !$dimensions || ($dimensions['mime']??'')!==$mime) fail_upload(415,'Choose a valid JPEG, PNG, WebP or GIF image.');
if($dimensions[0]*$dimensions[1]>40000000) fail_upload(413,'Image exceeds 40 megapixels.');
// A dedicated directory prevents overwrites of the original WordPress library.
$folder='cms-uploads/'.gmdate('Y/m');$directory=__DIR__.'/'.$folder;
if(!is_dir($directory) && !mkdir($directory,0755,true)) fail_upload(500,'Media directory is not writable.');
$name=bin2hex(random_bytes(20)).'.'.$extensions[$mime];
if(!move_uploaded_file($file['tmp_name'],$directory.'/'.$name)) fail_upload(500,'Could not save the image on Hostinger.');
chmod($directory.'/'.$name,0644);
http_response_code(201);echo json_encode(['url'=>'https://media.anjupankaj.com/'.$folder.'/'.$name]);
