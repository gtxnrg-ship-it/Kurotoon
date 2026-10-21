import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../runtime.dart';
import '../storage/kurotoon_database.dart';
import '../shop/kuru_collectibles.dart';

const _shopInk = Color(0xFF070812);
const _shopCyan = Color(0xFF83EAF7);
const _shopViolet = Color(0xFFB58CFF);
const _shopPink = Color(0xFFFF75C8);
const _silverKey = 'shop.wallet.silver.v1';
const _goldKey = 'shop.wallet.gold.v1';
const _ownedKey = 'shop.collection.owned.v1';
const _equippedKey = 'shop.collection.equipped.v1';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key, required this.runtime});
  final KurotoonRuntime runtime;

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> with TickerProviderStateMixin {
  bool _loading = true;
  bool _working = false;
  String? _error;
  int _silver = 0;
  int _gold = 0;
  String _category = 'All';
  String _tab = 'Discover';
  String? _equipped;
  Set<String> _owned = {};
  List<CacheEntryFile> _entries = const [];
  late final AnimationController _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
  late final AnimationController _sparkle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat(reverse: true);

  final List<String> _categories = const ['All','Stickers','Avatars','Seasonal','Outfits','Poses','Expressions','Characters'];

  @override
  void initState() { super.initState(); _reload(); }

  @override
  void dispose() { _ambient.dispose(); _sparkle.dispose(); super.dispose(); }

  Future<void> _reload() async {
    final db = widget.runtime.database;
    if (db == null) { if (mounted) setState(() { _loading = false; _error = 'Local storage is unavailable.'; }); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final values = await Future.wait<Object?>([
        db.getSetting<int>(_silverKey),
        db.getSetting<int>(_goldKey),
        db.getSetting<List<dynamic>>(_ownedKey),
        db.getSetting<String>(_equippedKey),
      ]);
      final entries = await db.loadCacheEntries();
      if (!mounted) return;
      setState(() {
        _silver = values[0] as int? ?? 800;
        _gold = values[1] as int? ?? 12;
        _owned = (values[2] as List<dynamic>?)?.whereType<String>().toSet() ?? {'kuru_happy','kuru_cry','kuru_sleepy'};
        _equipped = values[3] as String?;
        _entries = entries;
        _loading = false;
      });
      await _persistWallet();
      await db.setSetting(_ownedKey, _owned.toList()..sort());
    } on Object catch (error) {
      if (mounted) setState(() { _loading = false; _error = 'Your shop collection could not be loaded: ${error.runtimeType}.'; });
    }
  }

  Future<void> _persistWallet() async {
    final db = widget.runtime.database;
    if (db == null) return;
    await db.setSetting(_silverKey, _silver);
    await db.setSetting(_goldKey, _gold);
  }

  Future<void> _purchase(KuruCollectible item) async {
    if (_working || _owned.contains(item.id)) return;
    if (item.currency == CollectibleCurrency.achievement) {
      _showMessage('This collectible is earned through achievements, not purchased.');
      return;
    }
    setState(() => _working = true);
    try {
      final db = widget.runtime.database;
      if (db == null) throw StateError('Local storage is unavailable.');
      final result = await db.purchaseShopCollectible(
        itemId: item.id,
        price: item.price,
        useGold: item.currency == CollectibleCurrency.gold,
      );
      if (!mounted) return;
      if (result == ShopPurchaseStatus.insufficientFunds) {
        _showMessage('Not enough ${item.currency == CollectibleCurrency.gold ? 'gold' : 'silver'} coins yet. Keep exploring to earn more!');
        return;
      }
      if (result == ShopPurchaseStatus.alreadyOwned) {
        await _reload();
        _showMessage('You already own ${item.name}.');
        return;
      }
      await _reload();
      if (mounted) _showMessage('${item.name} added to your collection ✨');
    } on Object catch (error) {
      if (mounted) _showMessage('Purchase was not saved: ${error.runtimeType}.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _equip(KuruCollectible item) async {
    final db = widget.runtime.database;
    if (db == null || !_owned.contains(item.id)) return;
    await db.setSetting(_equippedKey, item.id);
    if (mounted) setState(() => _equipped = item.id);
    _showMessage('${item.name} equipped.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final visible = kuruCollectibles.where((item) {
      final categoryMatch = _category == 'All' || collectibleCategoryLabel(item.category) == _category;
      final tabMatch = _tab == 'Discover' || (_tab == 'Collection' && _owned.contains(item.id)) || (_tab == 'Locked' && !_owned.contains(item.id));
      return categoryMatch && tabMatch;
    }).toList();
    return Scaffold(
      backgroundColor: _shopInk,
      appBar: AppBar(
        title: const Text('Galaxy Shop', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .2)),
        backgroundColor: const Color(0xE6090B19),
        actions: [IconButton(tooltip: 'Refresh collection', onPressed: _loading || _working ? null : _reload, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Stack(children: [
        Positioned.fill(child: AnimatedBuilder(animation: _ambient, builder: (context, _) => CustomPaint(painter: _NebulaPainter(_ambient.value)))),
        RefreshIndicator(
          onRefresh: _reload,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 30), children: [
            _hero(),
            const SizedBox(height: 14),
            _wallet(),
            const SizedBox(height: 20),
            _journeyCard(),
            const SizedBox(height: 22),
            Row(children: [
              const Expanded(child: Text('YOUR COSMIC COLLECTION', style: TextStyle(color: _shopCyan, letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.w900))),
              Text('${_owned.length} / ${kuruCollectibles.length}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            _tabBar(),
            const SizedBox(height: 10),
            SizedBox(height: 42, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _categories.length, separatorBuilder: (_,__)=>const SizedBox(width:7), itemBuilder:(context,index) {
              final category = _categories[index]; final selected = _category == category;
              return ChoiceChip(label: Text(category), selected: selected, onSelected: (_) => setState(()=>_category=category), selectedColor: const Color(0xFF49336D), backgroundColor: const Color(0xFF111426), side: BorderSide(color: selected ? _shopViolet : Colors.white12), labelStyle: TextStyle(color:selected?Colors.white:Colors.white70,fontSize:12,fontWeight:selected?FontWeight.w800:FontWeight.w500));
            })),
            const SizedBox(height: 14),
            if (_error != null) _notice(_error!, warning: true),
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())),
            if (!_loading && visible.isEmpty) _emptyState(),
            if (!_loading) LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 4 : constraints.maxWidth >= 520 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                itemCount: visible.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .76),
                itemBuilder: (context,index) => _collectibleCard(visible[index]),
              );
            }),
            const SizedBox(height: 22),
            _storageSection(),
          ]),
        ),
      ]),
    );
  }

  Widget _hero() => Container(
    height: 190, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(begin: Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF30204F),Color(0xFF15172F),Color(0xFF091C2A)]),
      border: Border.all(color:_shopViolet.withValues(alpha:.45)),
    ),
    child: Stack(children:[
      Positioned.fill(child: AnimatedBuilder(animation:_ambient,builder:(context,_)=>CustomPaint(painter:_NebulaPainter(_ambient.value, dense:true)))),
      Positioned(right:18,top:28,child:Container(width:76,height:76,padding:const EdgeInsets.all(3),decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF111426),border:Border.all(color:_shopPink.withValues(alpha:.7),width:1.5),boxShadow:[BoxShadow(color:_shopPink.withValues(alpha:.22),blurRadius:18)]),child:ClipOval(child:Image.asset('assets/shop/kuru_hero_reference.jpg',fit:BoxFit.cover,errorBuilder:(context,error,stack)=>const Icon(Icons.pets_rounded,color:_shopPink,size:38))))),
      Positioned(right:-8,bottom:-20,child:AnimatedBuilder(animation:_sparkle,builder:(context,_)=>Transform.rotate(angle:math.sin(_sparkle.value*math.pi)*.08,child:Icon(Icons.auto_awesome_rounded,size:160,color:_shopViolet.withValues(alpha:.20))))),
      Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),decoration:BoxDecoration(color:_shopPink.withValues(alpha:.14),borderRadius:BorderRadius.circular(99),border:Border.all(color:_shopPink.withValues(alpha:.3))),child:const Text('THE KURU COLLECTION',style:TextStyle(color:_shopPink,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.4))),
        const Spacer(),
        const Text('Make this galaxy\nyours.',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900,height:1.05,letterSpacing:-.7)),
        const SizedBox(height:8),
        const Text('Collect little moments. Unlock a universe.',style:TextStyle(color:Colors.white70,fontSize:12)),
        const SizedBox(height:10),
        Row(children:[const Icon(Icons.auto_awesome,color:_shopCyan,size:15),const SizedBox(width:6),Text('${kuruCollectibles.length} unique collectibles',style:const TextStyle(color:_shopCyan,fontSize:11,fontWeight:FontWeight.w800))]),
      ])),
    ]),
  );

  Widget _wallet() => Row(children:[
    Expanded(child:_walletPill('Silver',_silver,Icons.circle_outlined,const Color(0xFFD7E0F1))),
    const SizedBox(width:10),
    Expanded(child:_walletPill('Gold',_gold,Icons.paid_rounded,const Color(0xFFFFD166))),
  ]);

  Widget _walletPill(String label,int balance,IconData icon,Color accent)=>Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:13),decoration:BoxDecoration(color:const Color(0xCC111426),borderRadius:BorderRadius.circular(17),border:Border.all(color:accent.withValues(alpha:.26))),child:Row(children:[Container(width:35,height:35,decoration:BoxDecoration(shape:BoxShape.circle,color:accent.withValues(alpha:.13)),child:Icon(icon,color:accent,size:20)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:Colors.white60,fontSize:11)),Text(balance.toString(),style:TextStyle(color:accent,fontWeight:FontWeight.w900,fontSize:20))])),const Icon(Icons.add_circle_outline_rounded,color:Colors.white38,size:17)]));

  Widget _journeyCard()=>Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:const Color(0xB5121325),borderRadius:BorderRadius.circular(18),border:Border.all(color:Colors.white.withValues(alpha:.08))),child:Row(children:[Container(width:42,height:42,decoration:BoxDecoration(color:_shopViolet.withValues(alpha:.13),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.explore_rounded,color:_shopViolet)),const SizedBox(width:12),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Your journey, your rewards',style:TextStyle(fontWeight:FontWeight.w800)),SizedBox(height:4),Text('Your collection and balances are saved on this device. Achievement-based rewards can be connected to reading milestones next.',style:TextStyle(color:Colors.white60,fontSize:11,height:1.4))]))]));

  Widget _tabBar()=>Container(padding:const EdgeInsets.all(4),decoration:BoxDecoration(color:const Color(0xFF101222),borderRadius:BorderRadius.circular(14)),child:Row(children:['Discover','Collection','Locked'].map((tab){final selected=_tab==tab;return Expanded(child:GestureDetector(onTap:()=>setState(()=>_tab=tab),child:AnimatedContainer(duration:const Duration(milliseconds:220),padding:const EdgeInsets.symmetric(vertical:10),decoration:BoxDecoration(color:selected?const Color(0xFF33234F):Colors.transparent,borderRadius:BorderRadius.circular(10)),child:Text(tab,textAlign:TextAlign.center,style:TextStyle(fontSize:12,fontWeight:selected?FontWeight.w800:FontWeight.w500,color:selected?Colors.white:Colors.white54)))));}).toList()));

  Widget _collectibleCard(KuruCollectible item) {
    final owned = _owned.contains(item.id);
    final equipped = _equipped == item.id;
    final accent = item.accent;
    return GestureDetector(
      onTap:()=>_showCollectible(item),
      child:Container(decoration:BoxDecoration(color:const Color(0xD6101221),borderRadius:BorderRadius.circular(18),border:Border.all(color:accent.withValues(alpha:owned ? .46 : .18)),boxShadow:[BoxShadow(color:accent.withValues(alpha:.06),blurRadius:14)]),clipBehavior:Clip.antiAlias,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Expanded(child:Stack(children:[
          Positioned.fill(child:DecoratedBox(decoration:BoxDecoration(gradient:RadialGradient(colors:[accent.withValues(alpha:.23),const Color(0xFF17182B).withValues(alpha:.25),Colors.transparent],stops:const[0,.58,1])))),
          Positioned(top:8,left:8,child:Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),decoration:BoxDecoration(color:accent.withValues(alpha:.12),borderRadius:BorderRadius.circular(7)),child:Text(item.rarity.toUpperCase(),style:TextStyle(fontSize:8,color:accent,fontWeight:FontWeight.w900,letterSpacing:.4)))),
          if(owned) Positioned(top:7,right:7,child:Icon(equipped?Icons.check_circle_rounded:Icons.verified_rounded,color:equipped?const Color(0xFF8FF0CE):Colors.white60,size:17)),
          Center(child:AnimatedBuilder(animation:_sparkle,builder:(context,_)=>Transform.translate(offset:Offset(0,math.sin((_sparkle.value*math.pi*2)+(item.id.hashCode%7))*(owned?3:1.5)),child:Container(width:74,height:74,decoration:BoxDecoration(shape:BoxShape.circle,color:accent.withValues(alpha:.09),border:Border.all(color:accent.withValues(alpha:.30)),boxShadow:[BoxShadow(color:accent.withValues(alpha:.14),blurRadius:20)]),child:Icon(item.icon,size:38,color:accent))))),
          if(!owned) Positioned(bottom:8,right:8,child:Icon(Icons.lock_outline_rounded,color:Colors.white.withValues(alpha:.45),size:15)),
        ])),
        Padding(padding:const EdgeInsets.fromLTRB(10,0,10,10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(item.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800)),
          const SizedBox(height:4),
          Row(children:[Icon(item.currency==CollectibleCurrency.gold?Icons.paid_rounded:Icons.circle_outlined,size:13,color:item.currency==CollectibleCurrency.gold?const Color(0xFFFFD166):const Color(0xFFD7E0F1)),const SizedBox(width:4),Expanded(child:Text(owned?(equipped?'Equipped':'Collected'):'${item.price} ${item.currency==CollectibleCurrency.gold?'gold':'silver'}',style:TextStyle(fontSize:10,color:owned?const Color(0xFF8FF0CE):Colors.white60,fontWeight:FontWeight.w700),maxLines:1,overflow:TextOverflow.ellipsis))]),
        ])),
      ])),
    );
  }

  Future<void> _showCollectible(KuruCollectible item) async {
    await showDialog<void>(context:context,builder:(context)=>_CollectibleDialog(item:item,owned:_owned.contains(item.id),equipped:_equipped==item.id,onPurchase:()=>_purchase(item),onEquip:()=>_equip(item)));
  }

  Widget _emptyState()=>Padding(padding:const EdgeInsets.symmetric(vertical:36),child:Column(children:[Icon(Icons.travel_explore_rounded,size:42,color:_shopViolet.withValues(alpha:.7)),const SizedBox(height:12),const Text('This corner of the galaxy is quiet.',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:5),const Text('Try another collection filter.',style:TextStyle(color:Colors.white54,fontSize:12))]));

  Widget _storageSection()=>ExpansionTile(title:const Text('DEVICE STORAGE',style:TextStyle(color:_shopCyan,letterSpacing:1.4,fontSize:11,fontWeight:FontWeight.w900)),subtitle:Text('${_entries.length} cached items · managed separately from collectibles',style:const TextStyle(color:Colors.white54,fontSize:11)),children:[if(_entries.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('No cached content yet.',style:TextStyle(color:Colors.white54))),for(final entry in _entries)ListTile(dense:true,leading:Icon(entry.entry.pinned?Icons.push_pin_rounded:Icons.insert_drive_file_outlined,color:entry.entry.pinned?_shopViolet:_shopCyan),title:Text(entry.entry.key,maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('${entry.entry.bytes} bytes · ${entry.entry.pinned?'Protected':'Disposable'}'),trailing:entry.entry.pinned?const Icon(Icons.lock_outline):IconButton(icon:const Icon(Icons.delete_outline_rounded),onPressed:_working?null:()=>_removeCache(entry)))]);

  Future<void> _removeCache(CacheEntryFile entry) async {
    final accepted=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Remove cached item?'),content:Text('Remove ${entry.entry.key}? This does not affect your collection, library, or reading progress.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Keep')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Remove'))]));
    if(accepted!=true||entry.entry.pinned)return;
    try { final cache=await widget.runtime.cacheStorage; await cache.remove(entry.entry.key); await _reload(); } on Object catch(error){_showMessage('Could not remove cache: ${error.runtimeType}.');}
  }

  Widget _notice(String message,{bool warning=false})=>Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:(warning?Colors.orangeAccent:Colors.white).withValues(alpha:.06),borderRadius:BorderRadius.circular(12)),child:Text(message,style:TextStyle(color:warning?Colors.orangeAccent:Colors.white70,fontSize:12)));

}

class _CollectibleDialog extends StatefulWidget {
  const _CollectibleDialog({required this.item,required this.owned,required this.equipped,required this.onPurchase,required this.onEquip});
  final KuruCollectible item; final bool owned; final bool equipped; final Future<void> Function() onPurchase; final Future<void> Function() onEquip;
  @override State<_CollectibleDialog> createState()=>_CollectibleDialogState();
}

class _CollectibleDialogState extends State<_CollectibleDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller=AnimationController(vsync:this,duration:Duration(milliseconds:widget.item.animation==CollectibleAnimation.tears?850:1350))..repeat(reverse:true);
  @override void dispose(){_controller.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final item=widget.item;
    return Dialog(backgroundColor:const Color(0xFF101222),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(26),side:BorderSide(color:item.accent.withValues(alpha:.5))),child:Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Align(alignment:Alignment.centerRight,child:IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close_rounded))),
      SizedBox(height:190,width:220,child:Stack(alignment:Alignment.center,children:[
        AnimatedBuilder(animation:_controller,builder:(context,_)=>Transform.rotate(angle:item.animation==CollectibleAnimation.orbit?_controller.value*math.pi*2:0,child:Container(width:150,height:150,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:item.accent.withValues(alpha:.35)),gradient:RadialGradient(colors:[item.accent.withValues(alpha:.22),const Color(0xFF17182B),Colors.transparent]))))),
        AnimatedBuilder(animation:_controller,builder:(context,_)=>Transform.translate(offset:_motion(item.animation,_controller.value),child:Transform.scale(scale:1+_scale(item.animation,_controller.value),child:Icon(item.icon,size:94,color:item.accent,shadows:[Shadow(color:item.accent.withValues(alpha:.65),blurRadius:24)])))),
        if(item.animation==CollectibleAnimation.tears) ...[for(var i=0;i<2;i++)AnimatedBuilder(animation:_controller,builder:(context,_)=>Positioned(left:85+i*46,top:85+(_controller.value*35),child:Icon(Icons.water_drop_rounded,size:15,color:const Color(0xFF7BD7FF).withValues(alpha:.4+.6*_controller.value))))],
        if(item.animation==CollectibleAnimation.hearts||item.animation==CollectibleAnimation.confetti||item.animation==CollectibleAnimation.sparkle) ...[for(var i=0;i<6;i++)AnimatedBuilder(animation:_controller,builder:(context,_)=>Positioned(left:12+((i*37)%185),top:10+((i*29+(_controller.value*35).round())%150),child:Icon(item.animation==CollectibleAnimation.hearts?Icons.favorite_rounded:Icons.auto_awesome_rounded,size:10+(i%3)*4,color:item.accent.withValues(alpha:.35+.6*_controller.value))))],
      ])),
      Text(item.name,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w900)),
      const SizedBox(height:6),
      Text(item.description,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70,height:1.4)),
      const SizedBox(height:12),
      Wrap(spacing:7,runSpacing:7,alignment:WrapAlignment.center,children:[_tag(item.rarity,item.accent),_tag(collectibleCategoryLabel(item.category),_shopCyan),if(item.eventOnly)_tag('LIMITED EVENT',_shopPink)]),
      const SizedBox(height:18),
      SizedBox(width:double.infinity,child:widget.owned?FilledButton.icon(onPressed:widget.equipped?null:()=>widget.onEquip(),icon:Icon(widget.equipped?Icons.check_circle:Icons.checkroom_rounded),label:Text(widget.equipped?'Equipped':'Equip collectible')):FilledButton.icon(onPressed:()=>widget.onPurchase(),icon:Icon(item.currency==CollectibleCurrency.gold?Icons.paid_rounded:Icons.shopping_bag_rounded),label:Text('Unlock · ${item.price} ${item.currency==CollectibleCurrency.gold?'gold':'silver'} coins'))),
      const SizedBox(height:6),
      Text('Unique ID: ${item.id}',style:const TextStyle(color:Colors.white30,fontSize:9)),
    ])));
  }
  Offset _motion(CollectibleAnimation animation,double t)=>switch(animation){CollectibleAnimation.bounce=>Offset(0,-10*math.sin(t*math.pi)),CollectibleAnimation.shake=>Offset(math.sin(t*math.pi*8)*4,0),CollectibleAnimation.float=>Offset(0,7*math.sin(t*math.pi*2)),CollectibleAnimation.orbit=>Offset(5*math.sin(t*math.pi*2),5*math.cos(t*math.pi*2)),_=>Offset.zero};
  double _scale(CollectibleAnimation animation,double t)=>switch(animation){CollectibleAnimation.pulse=>.06*math.sin(t*math.pi),CollectibleAnimation.bounce=>.035*math.sin(t*math.pi),_=>0};
  Widget _tag(String text,Color color)=>Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),decoration:BoxDecoration(color:color.withValues(alpha:.12),borderRadius:BorderRadius.circular(99),border:Border.all(color:color.withValues(alpha:.35))),child:Text(text,style:TextStyle(color:color,fontSize:10,fontWeight:FontWeight.w800)));
}

class _NebulaPainter extends CustomPainter {
  _NebulaPainter(this.progress,{this.dense=false}); final double progress; final bool dense;
  @override void paint(Canvas canvas,Size size){
    final p=Paint()..style=PaintingStyle.fill;
    final blobs=<({double x,double y,double r,Color color,double phase})>[
      (x:.12,y:.20,r:.27,color:const Color(0xFF6D3EC2),phase:0),
      (x:.76,y:.12,r:.23,color:const Color(0xFF1C7792),phase:1.2),
      (x:.55,y:.90,r:.32,color:const Color(0xFF9A2D81),phase:2.4),
      (x:.92,y:.78,r:.22,color:const Color(0xFF3458B6),phase:3.4),
    ];
    for(final b in blobs){final dx=math.sin(progress*math.pi*2+b.phase)*size.width*.06;final dy=math.cos(progress*math.pi*2+b.phase)*size.height*.07;final center=Offset(size.width*b.x+dx,size.height*b.y+dy);p.shader=RadialGradient(colors:[b.color.withValues(alpha:dense ? .22 : .13),b.color.withValues(alpha:.045),Colors.transparent]).createShader(Rect.fromCircle(center:center,radius:size.width*b.r));canvas.drawCircle(center,size.width*b.r,p);}
    p.shader=null;
    final count=dense?45:90;
    for(var i=0;i<count;i++){final seed=(i*7919%997)/997;final x=(seed*size.width+math.sin(progress*math.pi*2+i)*5)%size.width;final y=((i*37.7+progress*size.height*.22)%size.height);final alpha=.18+((math.sin(progress*math.pi*2+i)+1)*.18);p.color=Colors.white.withValues(alpha:alpha);canvas.drawCircle(Offset(x,y),i%13==0?1.5:.65,p);}
  }
  @override bool shouldRepaint(covariant _NebulaPainter old)=>old.progress!=progress||old.dense!=dense;
}
