#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreLocation/CLLocation.h>

#include <math.h>

const double pi = 3.14159265358979324;
const double a = 6378245.0;
const double ee = 0.00669342162296594323;

double transformLat(double x, double y);
double transformLon(double x, double y);
bool outOfChina(double lat, double lon);

void transform(double wgLat, double wgLon, double *mgLat, double *mgLon)
{
    if (outOfChina(wgLat, wgLon))
    {
        *mgLat = wgLat;
        *mgLon = wgLon;
        return;
    }
    double dLat = transformLat(wgLon - 105.0, wgLat - 35.0);
    double dLon = transformLon(wgLon - 105.0, wgLat - 35.0);
    double radLat = wgLat / 180.0 * pi;
    double magic = sin(radLat);
    magic = 1 - ee * magic * magic;
    double sqrtMagic = sqrt(magic);
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi);
    dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * pi);
    *mgLat = wgLat + dLat;
    *mgLon = wgLon + dLon;
}

bool outOfChina(double lat, double lon)
{
    if (lon < 72.004 || lon > 137.8347)
        return true;
    if (lat < 0.8293 || lat > 55.8271)
        return true;
    return false;
}

double transformLat(double x, double y)
{
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x));
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
}

double transformLon(double x, double y)
{
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x));
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
}

/* ------- Begin hooking functions ------- */

%hook FMFLocation
- (void)updateLatitude:(id)lat longitude:(id)lng altitude:(id)alt horizontalAccuracy:(id)acc verticalAccuracy:(id)acc5 course:(id)c speed:(id)s timestamp:(id)ts {
    double nlat,nlng;
    transform([lat doubleValue],[lng doubleValue], &nlat, &nlng);
    NSNumber *olat=[NSNumber numberWithDouble:nlat];
    NSNumber *olng=[NSNumber numberWithDouble:nlng];
    %orig(olat,olng,alt,acc,acc5,c,s,ts); 
}
%end

%hook MyLocationController 
-(void)updateCurrentLocationTo:(id)to{
    CLLocation *lp=(CLLocation *)to;
    double nlat,nlng;
    NSDictionary *prefs=[[NSDictionary alloc] initWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.weishi.fmfipspoofer-prefs.plist"
        ];
    if ([[prefs objectForKey:@"enableLocationSpoofing"] boolValue]){
        double spoofedLat, spoofedLng;
        spoofedLat=[[prefs objectForKey:@"latitude"] doubleValue];
        spoofedLng=[[prefs objectForKey:@"longitude"] doubleValue];
        if ([[prefs objectForKey:@"reportShiftedLocation"] boolValue]==NO){
            transform(spoofedLat, spoofedLng, &nlat, &nlng);
            nlat=spoofedLat-(nlat-spoofedLat);
            nlng=spoofedLng-(nlng-spoofedLng);
        }else{
            //Pad a shift and let remote user cancel the shift. 
            transform(spoofedLat, spoofedLng, &nlat, &nlng);
            nlat-=3*(nlat-spoofedLat);
            nlng-=3*(nlng-spoofedLng);
        }
    }else{
        //Incoming coordinates are true GPS coordinates.
        if ([[prefs objectForKey:@"reportShiftedLocation"] boolValue]==NO){
            //For unjailbroken devices, use true GPS coordinates.
            nlat=lp.coordinate.latitude;
            nlng=lp.coordinate.longitude;
        }else{
            //Pad a shift and let remote user cancel the shift. 
            transform(lp.coordinate.latitude, lp.coordinate.longitude, &nlat, &nlng);
            nlat-=2*(nlat-lp.coordinate.latitude);
            nlng-=2*(nlng-lp.coordinate.longitude);
        }
    }
    CLLocation *c = [[[CLLocation alloc] 
        initWithCoordinate:CLLocationCoordinate2DMake(nlat, nlng)
        altitude:lp.altitude
        horizontalAccuracy:lp.horizontalAccuracy
        verticalAccuracy:lp.verticalAccuracy
        timestamp:lp.timestamp] autorelease];
    %orig(c);
}
%end

%hook AOSFindBaseServiceProvider
-(void)sendCurrentLocation:(id)fp8 isFinished:(BOOL)fp12 forCmd:(id)fp16 withReason:(int)fp20 andAccuracyChange:(double)fp24{
    CLLocation *lp=(CLLocation *)fp8;
    double nlat,nlng;
    NSDictionary *prefs=[[NSDictionary alloc] initWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.weishi.fmfipspoofer-prefs.plist"
        ];
    if ([[prefs objectForKey:@"enableLocationSpoofing"] boolValue]){
        double spoofedLat, spoofedLng;
        spoofedLat=[[prefs objectForKey:@"latitude"] doubleValue];
        spoofedLng=[[prefs objectForKey:@"longitude"] doubleValue];
        if ([[prefs objectForKey:@"reportShiftedLocation"] boolValue]==NO){
            nlat=spoofedLat;
            nlng=spoofedLng;
        }else{
            //Pad a shift and let remote user cancel the shift. 
            transform(spoofedLat, spoofedLng, &nlat, &nlng);
            nlat=spoofedLat-(nlat-spoofedLat);
            nlng=spoofedLng-(nlng-spoofedLng);
        }
    }else{
        //Incoming coordinates have been shifted already.
        if ([[prefs objectForKey:@"reportShiftedLocation"] boolValue]==NO){
            //For unjailbroken devices, convert to true GPS coordinates
            transform(lp.coordinate.latitude, lp.coordinate.longitude, &nlat, &nlng);
        }else{
            //Already shifted and let remote user cancel the shift. 
            nlat=lp.coordinate.latitude;
            nlng=lp.coordinate.longitude;
        }
    }
    CLLocation *c = [[[CLLocation alloc] 
        initWithCoordinate:CLLocationCoordinate2DMake(nlat, nlng)
        altitude:lp.altitude
        horizontalAccuracy:lp.horizontalAccuracy
        verticalAccuracy:lp.verticalAccuracy
        timestamp:lp.timestamp] autorelease];
    %orig(c,fp12,fp16,fp20,fp24);
}
%end
