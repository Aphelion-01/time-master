@main struct TimeModelChecks {
 static func main() {
  let now=Date(), cal=Calendar.current
  let start=cal.date(byAdding:.day,value:-23,to:now)!
  let end=cal.date(byAdding:.day,value:19,to:now)!
  let normal=Event(title:"test",start:start,end:end)
  assert(normal.totalDays==42 && normal.remaining==19)
  assert(abs(normal.ratio - 19.0/42.0)<0.001)
  let past=Event(title:"past",start:now.addingTimeInterval(-86400*3),end:now.addingTimeInterval(-86400))
  assert(past.remaining==0 && past.ratio==0 && past.status=="已到期")
  let future=Event(title:"future",start:now.addingTimeInterval(86400),end:now.addingTimeInterval(86400*3))
  assert(future.ratio==1 && future.status=="尚未开始")
  let today=Event(title:"today",start:start,end:cal.startOfDay(for:now))
  assert(today.remaining==0)
  let data=try! JSONEncoder().encode([normal,past,future])
  assert(try! JSONDecoder().decode([Event].self,from:data)==[normal,past,future])
  let screen=CGRect(x:0,y:0,width:1440,height:1600)
  let size=CGSize(width:458,height:362)
  func snap(_ x:CGFloat,_ y:CGFloat,_ neighbors:[CGRect]=[]) -> CGRect {
    CardSnap.snapped(CGRect(origin:CGPoint(x:x,y:y),size:size),screens:[screen],neighbors:neighbors)
  }
  assert(snap(5,200).minX == -2) // Visible card, excluding transparent padding, is 12pt from screen.
  assert(snap(250,300).origin == CGPoint(x:250,y:300))
  let neighbor=CGRect(x:600,y:300,width:458,height:362)
  assert(snap(150,300,[neighbor]).minX == 158) // 12pt gap between visible cards.
  assert(snap(600,650,[neighbor]).minY == 646)
  assert(snap(150,950,[neighbor]).minX == 150) // Do not align to distant cards.
  assert(snap(1000,200).minX == 984) // Right edge, including threshold boundary.
  let negative=CardSnap.snapped(CGRect(x:-1435,y:200,width:458,height:362),screens:[CGRect(x:-1440,y:0,width:1440,height:1600),screen],neighbors:[])
  assert(negative.minX == -1442) // Monitor to the left of the primary screen.
  let exact=CGRect(x:200,y:200,width:458,height:362)
  assert(CardSnap.snapped(exact,screens:[screen],neighbors:[],threshold:0)==exact)
  for layout in CardLayout.allCases { assert(CardLayout.resolve(layout.size)==layout) }
  assert(CardLayout.resolve(CGSize(width:359,height:334)) == .compact)
  assert(CardLayout.resolve(CGSize(width:360,height:334)) == .standard)
  assert(CardLayout.resolve(CGSize(width:560,height:339)) == .wide)
  assert(CardLayout.resolve(CGSize(width:560,height:340)) == .expanded)
  assert(CardGeometry.clamp(CGSize(width:1,height:1)) == CardGeometry.minimum)
  assert(CardGeometry.clamp(CGSize(width:9999,height:9999)) == CardGeometry.maximum)
  assert(CardGeometry.clamp(CGSize(width:Double.infinity,height:30)) == CardLayout.standard.size)
  let resized=CardGeometry.resize(CGRect(x:100,y:200,width:458,height:362),translation:CGSize(width:210,height:94))
  assert(resized.maxY == 562 && resized.minX == 100 && resized.width == 668 && resized.height == 268)
  assert(CardLayout.resolve(CGSize(width:resized.width-28,height:resized.height-28)) == .wide)
  let feedback=DragFeedback.resolve(vx:99999,vy:-99999)
  assert(abs(feedback.angle)<=1.8 && feedback.stretchX<=1.012 && feedback.stretchY<=1.012 && abs(feedback.lagX)<=5)
  let stationary=DragFeedback.resolve(vx:0,vy:0)
  assert(stationary.angle==0 && stationary.stretchX==1 && stationary.stretchY==1)
  let invalid=DragFeedback.resolve(vx:Double.nan,vy:Double.infinity)
  assert(invalid.angle.isFinite && invalid.stretchX.isFinite)
  var legacy=try! JSONSerialization.jsonObject(with:JSONEncoder().encode(normal)) as! [String:Any]
  legacy.removeValue(forKey:"cardWidth"); legacy.removeValue(forKey:"cardHeight")
  let migrated=try! JSONDecoder().decode(Event.self,from:JSONSerialization.data(withJSONObject:legacy))
  assert(migrated.cardSize == CardLayout.standard.size)
  var custom=normal; custom.cardWidth=640; custom.cardHeight=240
  assert(try! JSONDecoder().decode(Event.self,from:JSONEncoder().encode(custom)).cardSize == custom.cardSize)
  let reference=Date(timeIntervalSinceReferenceDate:800000000)
  let a=Event(title:"A",start:reference.addingTimeInterval(-23*86400),end:reference.addingTimeInterval(19*86400))
  let b=Event(title:"B",start:reference,end:reference.addingTimeInterval(37*86400))
  let expired=Event(title:"expired",start:reference.addingTimeInterval(-5*86400),end:reference.addingTimeInterval(-86400))
  var group=EventGroup(title:"Test",eventIDs:[b.id,a.id,a.id,expired.id,UUID()])
  assert(group.uniqueIDs.count==4)
  assert(group.members(in:[a,b,expired],now:reference).map(\.id)==[a.id,b.id,expired.id])
  group.sort = .manual
  assert(group.members(in:[a,b,expired],now:reference).map(\.id)==[b.id,a.id,expired.id])
  var edited=a; edited.title="Updated"
  assert(group.members(in:[edited,b],now:reference).last?.title=="Updated")
  assert(group.members(in:[b],now:reference).count==1)
  let axis=SharedTimeAxis(events:[a,b,expired],now:reference)
  assert(abs(axis.fraction(for:a.end)-19.0/37.0)<0.000001 && axis.fraction(for:b.end)==1 && axis.fraction(for:expired.end)==0)
  assert(SharedTimeAxis(events:[],now:reference).fraction(for:reference)==0)
  assert(GroupGeometry.columns(width:559)==1 && GroupGeometry.columns(width:560)==2 && GroupGeometry.columns(width:800)==3)
  assert(GroupGeometry.clamp(CGSize(width:1,height:1))==GroupGeometry.minimum)
  assert(GroupGeometry.clamp(CGSize(width:9999,height:9999))==GroupGeometry.maximum)
  let groupFrame=GroupGeometry.resize(CGRect(x:30,y:200,width:588,height:448),translation:CGSize(width:100,height:60))
  assert(groupFrame.minX==30 && groupFrame.maxY==648)
  let oldBackup=try! BackupDocument.read(JSONEncoder().encode([a,b]))
  assert(oldBackup.groups.isEmpty && oldBackup.events.count==2)
  let clean=EventGroup(title:"Test",eventIDs:[b.id,a.id])
  let backup=BackupDocument(events:[a,b],groups:[clean])
  assert(try! BackupDocument.read(JSONEncoder().encode(backup)).groups==[clean])
  var bad=backup; bad.groups[0].eventIDs.append(UUID())
  assert((try? BackupDocument.read(JSONEncoder().encode(bad)))==nil)
  bad=backup; bad.version=999
  assert((try? BackupDocument.read(JSONEncoder().encode(bad)))==nil)
  print("PASS: shared event references, member pruning/deduplication, sorting, common axis, group resize, legacy/new backup and invalid-reference rejection")
  print("PASS: four layout thresholds, min/max resizing, top-left anchor, finite bounded motion, legacy migration and size persistence")
  print("PASS: screen edges, card adjacency, vertical stacking, distant neighbors, threshold boundary, negative monitor coordinates")
  print("PASS: 42-day range, 19-day remainder, precise ratio, expired, not-started, day boundary, JSON round trip")
 }
}
