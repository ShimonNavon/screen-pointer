import sys
import base64,datetime as dt,importlib.util,json,pathlib,tempfile,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
spec=importlib.util.spec_from_file_location('point',pathlib.Path(__file__).resolve().parents[1]/'tools/point_mcp.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
PNG=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1EAAAAASUVORK5CYII=')
class CaptureTests(unittest.TestCase):
 def test_capture_lifecycle_and_path_boundaries(self):
  with tempfile.TemporaryDirectory() as tmp:
   mod.DIRECTORY=pathlib.Path(tmp);root=mod.DIRECTORY
   self.assertTrue(mod.latest_point()['isError'])
   ident='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';name=ident+'.png'
   status={'state':'ready','id':ident};meta={'id':ident,'image':name,'captured_at':dt.datetime.now(dt.timezone.utc).isoformat(),'pointer':{'x':0,'y':0}}
   def save():
    (root/'status.json').write_text(json.dumps(status));(root/'latest.json').write_text(json.dumps(meta))
   (root/name).write_bytes(PNG);save()
   self.assertEqual(mod.latest_point()['content'][1]['data'],base64.b64encode(PNG).decode())
   status['state']='failed';save();self.assertTrue(mod.latest_point()['isError'])
   status['state']='ready';meta['captured_at']=(dt.datetime.now(dt.timezone.utc)-dt.timedelta(minutes=3)).isoformat();save()
   self.assertTrue(mod.latest_point()['isError']);self.assertNotIn('isError',mod.latest_point(True))
   meta['image']='../private.png';save();self.assertTrue(mod.latest_point(True)['isError'])
   meta['image']=name;status['id']='different';save();self.assertTrue(mod.latest_point(True)['isError'])
if __name__=='__main__':unittest.main()
