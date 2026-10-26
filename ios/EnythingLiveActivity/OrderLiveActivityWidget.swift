import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct OrderLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: OrderLiveActivityAttributes.self) { context in
      // ── Lock Screen & Notification Center Live Activity Banner ───────────
      LockScreenLiveActivityView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        // ── Expanded Dynamic Island (Long Press) ───────────────────────────
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 8) {
            ZStack {
              RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 1.0, green: 0.35, blue: 0.0).opacity(0.2))
                .frame(width: 32, height: 32)
              Image(systemName: context.state.statusKey == "out_for_delivery" ? "scooter" : "fork.knife")
                .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
                .font(.system(size: 16, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(context.attributes.shopName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
              Text("Order #\(context.attributes.orderNumber)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
            }
          }
          .padding(.leading, 8)
        }

        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 2) {
              Text("\(context.state.etaMinutes)")
                .font(.system(size: 18, weight: .black))
                .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
              Text("mins")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
            }
            Text("Est. Arrival")
              .font(.system(size: 10))
              .foregroundColor(.gray)
          }
          .padding(.trailing, 8)
        }

        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text(context.state.statusHeadline)
              .font(.system(size: 14, weight: .bold))
              .foregroundColor(.white)
              .lineLimit(1)

            // Sleek orange gradient progress bar
            GeometryReader { geo in
              ZStack(alignment: .leading) {
                Capsule()
                  .fill(Color.white.opacity(0.15))
                  .frame(height: 6)

                Capsule()
                  .fill(
                    LinearGradient(
                      colors: [
                        Color(red: 1.0, green: 0.5, blue: 0.0),
                        Color(red: 1.0, green: 0.25, blue: 0.0)
                      ],
                      startPoint: .leading,
                      endPoint: .trailing
                    )
                  )
                  .frame(
                    width: max(geo.size.width * CGFloat(min(max(context.state.progress, 0.05), 1.0)), 12),
                    height: 6
                  )
                  .animation(.easeInOut(duration: 0.5), value: context.state.progress)
              }
            }
            .frame(height: 6)

            HStack {
              if let otp = context.state.deliveryOtp, !otp.isEmpty {
                HStack(spacing: 4) {
                  Image(systemName: "key.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.2))
                  Text("OTP: \(otp)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.2))
                }
              } else if let rider = context.state.riderName, !rider.isEmpty {
                HStack(spacing: 4) {
                  Image(systemName: "bicycle")
                    .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
                  Text(rider)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                }
              } else {
                Text("💳 Prepaid · ₹0 To Collect")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundColor(.white.opacity(0.8))
              }
              Spacer()
              if context.state.isMultiShop {
                Text("🛒 Multi-Store Order")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundColor(Color(red: 1.0, green: 0.5, blue: 0.0))
              }
            }
          }
          .padding(.horizontal, 10)
          .padding(.bottom, 6)
        }
      } compactLeading: {
        // ── Compact Leading: Scooter / Food Glyph ─────────────────────────
        ZStack {
          Circle()
            .fill(Color(red: 1.0, green: 0.35, blue: 0.0).opacity(0.2))
            .frame(width: 22, height: 22)
          Image(systemName: context.state.statusKey == "out_for_delivery" ? "scooter" : "frying.pan.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 12, height: 12)
            .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
        }
      } compactTrailing: {
        // ── Compact Trailing: Bold ETA Countdown ─────────────────────────
        Text("\(context.state.etaMinutes)m")
          .font(.system(size: 12, weight: .black))
          .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
      } minimal: {
        // ── Minimal: Delivery Dot / Scooter ──────────────────────────────
        Image(systemName: "scooter")
          .resizable()
          .scaledToFit()
          .frame(width: 12, height: 12)
          .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
      }
    }
  }
}

// ── Swiggy-Style Lock Screen Live Activity Card ──────────────────────────────
@available(iOS 16.1, *)
struct LockScreenLiveActivityView: View {
  let context: ActivityViewContext<OrderLiveActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // 1. Top Header: "Arriving in 9 mins" + Brand Icon
      HStack(alignment: .center) {
        HStack(spacing: 4) {
          Text("Arriving in")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)

          Text("\(context.state.etaMinutes) mins")
            .font(.system(size: 15, weight: .black))
            .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
        }

        Spacer()

        // Enything Brand Badge
        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color(red: 1.0, green: 0.35, blue: 0.0))
            .frame(width: 28, height: 28)
          Text("E")
            .font(.system(size: 16, weight: .black))
            .foregroundColor(.white)
        }
      }

      // 2. Middle Row: Big Bold Status Headline + Culinary/Delivery Graphic
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(context.state.statusHeadline)
            .font(.system(size: 20, weight: .heavy))
            .foregroundColor(.white)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

          if context.state.isMultiShop {
            Text("🛒 Multi-Store Order · \(context.attributes.shopName)")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.2))
          } else {
            Text(context.attributes.shopName)
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.gray)
          }
        }

        Spacer()

        // 3D Cooking Pan / Scooter Graphic representation
        ZStack {
          Circle()
            .fill(
              RadialGradient(
                colors: [
                  Color(red: 1.0, green: 0.35, blue: 0.0).opacity(0.35),
                  Color.clear
                ],
                center: .center,
                startRadius: 4,
                endRadius: 36
              )
            )
            .frame(width: 60, height: 60)

          Image(systemName: context.state.statusKey == "out_for_delivery" ? "scooter" : "frying.pan.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 38, height: 38)
            .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
            .shadow(color: Color(red: 1.0, green: 0.35, blue: 0.0).opacity(0.5), radius: 6, x: 0, y: 2)
        }
      }

      // 3. Bottom Progress Bar: Orange Gradient Fill
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color(white: 0.22))
            .frame(height: 7)

          Capsule()
            .fill(
              LinearGradient(
                colors: [
                  Color(red: 1.0, green: 0.45, blue: 0.0),
                  Color(red: 1.0, green: 0.25, blue: 0.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(
              width: max(geo.size.width * CGFloat(min(max(context.state.progress, 0.05), 1.0)), 14),
              height: 7
            )
            .animation(.easeInOut(duration: 0.6), value: context.state.progress)
        }
      }
      .frame(height: 7)

      // 4. Financial & Rider & OTP Footer
      HStack {
        if let otp = context.state.deliveryOtp, !otp.isEmpty {
          HStack(spacing: 6) {
            Image(systemName: "key.fill")
              .font(.system(size: 10))
              .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.2))
            Text("Delivery OTP:")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.white.opacity(0.9))
            Text(otp)
              .font(.system(size: 13, weight: .black))
              .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.2))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.black.opacity(0.45))
              .cornerRadius(4)
          }
        } else if let rider = context.state.riderName, !rider.isEmpty {
          HStack(spacing: 4) {
            Image(systemName: "person.fill")
              .font(.system(size: 10))
              .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0))
            Text("Partner: \(rider)")
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(.white.opacity(0.85))
          }
        } else {
          Text("💳 100% Prepaid · Zero Cash On Delivery")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.6))
        }

        Spacer()

        Text("ENYTHING INSTANT")
          .font(.system(size: 9, weight: .black))
          .tracking(1.0)
          .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.0).opacity(0.8))
      }
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 22)
        .fill(Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.96))
    )
  }
}
