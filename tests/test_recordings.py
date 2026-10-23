import json,pathlib,sys,tempfile,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
import recordings
class RecordingTests(unittest.TestCase):
 def test_ready_state_and_frame_confinement(self):
  with tempfile.TemporaryDirectory() as tmp:
   recordings.ROOT=pathlib.Path(tmp);ident='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';folder=recordings.ROOT/ident;folder.mkdir();(folder/'frames').mkdir()
   (folder/'frames/0000.jpg').write_bytes(b'\xff\xd8test')
   meta={'id':ident,'state':'ready','frames':[{'image':'frames/0000.jpg','index':0,'time':0.0}],'events':[]}
   (recordings.ROOT/'latest.json').write_text(json.dumps({'id':ident,'state':'ready'}))
   def save(): (folder/'session.json').write_text(json.dumps(meta))
   save();self.assertEqual(len(recordings.recording_result()['content']),3)
   with self.assertRaises(ValueError):recordings.recording_result(indices=[True])
   with self.assertRaises(ValueError):recordings.recording_result('../secret',[0])
   meta['state']='failed';save()
   with self.assertRaises(ValueError):recordings.recording_result()
   meta['state']='ready';meta['frames'][0]['image']='../private.jpg';save()
   with self.assertRaises(ValueError):recordings.recording_result()
if __name__=='__main__':unittest.main()
