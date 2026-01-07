import {
  CDPHooksProvider,
  useIsInitialized,
  useIsSignedIn,
  useSignOut,
  Config,
} from "@coinbase/cdp-hooks";
import { StatusBar } from "expo-status-bar";
import { StyleSheet, Text, View, Alert, ScrollView, SafeAreaView, TouchableOpacity } from "react-native";
import { NavigationContainer } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import Icon from 'react-native-vector-icons/Ionicons';

import Transaction from "./Transaction";
import { ThemeProvider, useTheme } from "./theme/ThemeContext";
import { SignInForm } from "./components/SignInForm";
import { DarkModeToggle } from "./components/DarkModeToggle";
import { WalletHeader } from "./components/WalletHeader";

const Tab = createBottomTabNavigator();

const cdpConfig = {
  projectId: process.env.EXPO_PUBLIC_CDP_PROJECT_ID,
  basePath: process.env.EXPO_PUBLIC_CDP_BASE_PATH,
  ethereum: {
    createOnLogin: "smart",
  },
  useMock: process.env.EXPO_PUBLIC_CDP_USE_MOCK === "true",
  nativeOAuthCallback: process.env.EXPO_PUBLIC_NATIVE_OAUTH_CALLBACK,
} as Config;

/**
 * A multi-step authentication component that handles email and SMS-based sign-in flows.
 *
 * The component manages authentication states:
 * 1. Initial state: Displays a welcome screen with sign-in options
 * 2. Input: Collects and validates the user's email address or phone number
 * 3. OTP verification: Validates the one-time password sent to the user's email or SMS
 *
 * Features:
 * - Toggle between email and SMS authentication
 * - Email and phone number validation
 * - 6-digit OTP validation
 * - Loading states during API calls
 * - Error handling for failed authentication attempts
 * - Cancelable workflow with state reset
 *
 * @returns {JSX.Element} The rendered sign-in form component
 */
// VPN Dashboard Screen Component
function VPNDashboardScreen() {
  const { colors } = useTheme();
  const styles = createStyles(colors);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.section}>
        <Text style={styles.title}>VPN Status</Text>
        <View style={styles.statusContainer}>
          <Text style={[styles.statusText, { color: colors.text }]}>Disconnected</Text>
          <TouchableOpacity style={styles.connectButton}>
            <Text style={styles.buttonText}>Connect VPN</Text>
          </TouchableOpacity>
        </View>
      </View>
      
      <View style={styles.section}>
        <Text style={styles.title}>Server Location</Text>
        <Text style={{ color: colors.text }}>United States (Recommended)</Text>
      </View>
      
      <View style={styles.section}>
        <Text style={styles.title}>Connection Speed</Text>
        <Text style={{ color: colors.text }}>Fast</Text>
      </View>
    </SafeAreaView>
  );
}

// Subscription Management Screen Component
function SubscriptionScreen() {
  const { colors } = useTheme();
  const styles = createStyles(colors);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.section}>
        <Text style={styles.title}>Your Plan</Text>
        <Text style={{ color: colors.text }}>Free Tier - 10GB/month</Text>
        <TouchableOpacity style={[styles.upgradeButton, { backgroundColor: '#4CAF50' }]}>
          <Text style={styles.buttonText}>Upgrade to Premium</Text>
        </TouchableOpacity>
      </View>
      
      <View style={styles.section}>
        <Text style={styles.title}>Payment Method</Text>
        <Text style={{ color: colors.text }}>Coinbase Wallet Connected</Text>
        <Text style={{ color: colors.text, fontSize: 12, marginTop: 5 }}>Pay with cryptocurrency</Text>
      </View>
      
      <View style={styles.section}>
        <Text style={styles.title}>Subscription Options</Text>
        <TouchableOpacity style={styles.planOption}>
          <Text style={styles.planTitle}>Monthly Plan</Text>
          <Text style={styles.planPrice}>$9.99/month</Text>
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.planOption}>
          <Text style={styles.planTitle}>Annual Plan</Text>
          <Text style={styles.planPrice}>$99.99/year</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

// Main VPN Application Component
function VPNApp() {
  const { isInitialized } = useIsInitialized();
  const { isSignedIn } = useIsSignedIn();
  const { signOut } = useSignOut();
  const { colors, isDarkMode } = useTheme();

  const handleSignOut = async () => {
    try {
      await signOut();
    } catch (error) {
      Alert.alert("Error", error instanceof Error ? error.message : "Failed to sign out.");
    }
  };

  const createStyles = (colors: any) =>
    StyleSheet.create({
      container: {
        flex: 1,
        backgroundColor: colors.background,
      },
      section: {
        padding: 20,
        borderBottomWidth: 1,
        borderBottomColor: colors.border,
      },
      title: {
        fontSize: 18,
        fontWeight: 'bold',
        marginBottom: 10,
        color: colors.text,
      },
      statusContainer: {
        alignItems: 'center',
      },
      statusText: {
        fontSize: 16,
        marginBottom: 15,
      },
      connectButton: {
        backgroundColor: '#2196F3',
        paddingVertical: 12,
        paddingHorizontal: 30,
        borderRadius: 25,
      },
      upgradeButton: {
        paddingVertical: 12,
        paddingHorizontal: 30,
        borderRadius: 25,
        marginTop: 10,
      },
      buttonText: {
        color: 'white',
        fontWeight: 'bold',
        textAlign: 'center',
      },
      planOption: {
        backgroundColor: colors.cardBackground,
        padding: 15,
        borderRadius: 8,
        marginBottom: 10,
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
      },
      planTitle: {
        fontSize: 16,
        fontWeight: 'bold',
        color: colors.text,
      },
      planPrice: {
        fontSize: 16,
        color: colors.text,
      },
      centerContent: {
        flex: 1,
        justifyContent: "center",
        alignItems: "center",
        padding: 20,
      },
      text: {
        fontSize: 16,
        textAlign: "center",
        color: colors.text,
      },
    });

  const styles = createStyles(colors);

  if (!isInitialized) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.centerContent}>
          <Text style={styles.text}>Initializing CDP...</Text>
        </View>
        <StatusBar style={isDarkMode ? "light" : "dark"} />
      </SafeAreaView>
    );
  }

  if (!isSignedIn) {
    return (
      <SafeAreaView style={styles.container}>
        <SignInForm />
        <StatusBar style={isDarkMode ? "light" : "dark"} />
      </SafeAreaView>
    );
  }

  // Render the tab navigator when user is signed in
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ focused, color, size }) => {
          let iconName = '';

          if (route.name === 'VPN') {
            iconName = focused ? 'power' : 'power-outline';
          } else if (route.name === 'Subscription') {
            iconName = focused ? 'card' : 'card-outline';
          } else if (route.name === 'Wallet') {
            iconName = focused ? 'wallet' : 'wallet-outline';
          }

          return <Icon name={iconName} size={size} color={color} />;
        },
        tabBarActiveTintColor: '#2196F3',
        tabBarInactiveTintColor: 'gray',
        headerShown: false,
      })}
    >
      <Tab.Screen name="VPN">
        {(props) => <VPNDashboardScreen {...props} />}
      </Tab.Screen>
      <Tab.Screen name="Subscription">
        {(props) => <SubscriptionScreen {...props} onSignOut={handleSignOut} />}
      </Tab.Screen>
      <Tab.Screen name="Wallet">
        {(props) => (
          <SafeAreaView style={styles.container}>
            <WalletHeader onSignOut={handleSignOut} />
            <ScrollView
              showsVerticalScrollIndicator={false}
              contentContainerStyle={{ padding: 20 }}
            >
              <View style={{ width: "100%", alignItems: "center", marginBottom: 20 }}>
                <Transaction onSuccess={() => console.log("Transaction successful!")} />
              </View>
            </ScrollView>
          </SafeAreaView>
        )}
      </Tab.Screen>
    </Tab.Navigator>
  );
}

/**
 * The main component that wraps the CDPApp component and provides the CDPHooksProvider.
 *
 * @returns {JSX.Element} The rendered main component
 */
export default function App() {
  // Check if project ID is empty or the placeholder value
  const projectId = process.env.EXPO_PUBLIC_CDP_PROJECT_ID;
  const isPlaceholderProjectId = !projectId || projectId === "your-project-id-here";

  if (isPlaceholderProjectId) {
    return (
      <ThemeProvider>
        <SafeAreaView
          style={{
            flex: 1,
            backgroundColor: "#f5f5f5",
            justifyContent: "center",
            alignItems: "center",
            padding: 20,
          }}
        >
          <Text
            style={{
              fontSize: 24,
              fontWeight: "bold",
              color: "#333",
              textAlign: "center",
              marginBottom: 16,
            }}
          >
            ⚠️ CDP Project ID Required
          </Text>
          <Text
            style={{
              fontSize: 16,
              color: "#666",
              textAlign: "center",
              lineHeight: 24,
              marginBottom: 24,
            }}
          >
            Please configure your CDP project ID in the .env file. Create a .env file in the project
            root and add your CDP project ID.
          </Text>
          <View
            style={{
              backgroundColor: "#f0f0f0",
              padding: 16,
              borderRadius: 8,
              borderWidth: 1,
              borderColor: "#ddd",
            }}
          >
            <Text
              style={{ fontFamily: "monospace", fontSize: 14, color: "#333", textAlign: "center" }}
            >
              EXPO_PUBLIC_CDP_PROJECT_ID=your-actual-project-id
            </Text>
          </View>
        </SafeAreaView>
      </ThemeProvider>
    );
  }

  return (
    <CDPHooksProvider config={cdpConfig}>
      <ThemeProvider>
        <NavigationContainer>
          <VPNApp />
        </NavigationContainer>
      </ThemeProvider>
    </CDPHooksProvider>
  );
}
