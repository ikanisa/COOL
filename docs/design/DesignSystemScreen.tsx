import React, { useState } from 'react';
import { 
  ArrowLeft, 
  Bell, 
  Search, 
  User, 
  CreditCard, 
  Wallet, 
  ScanFace, 
  ShoppingBag, 
  Users, 
  Zap, 
  Shield, 
  CheckCircle2,
  Info,
  MoreVertical,
  Settings,
  LogOut,
  Mail,
  Lock,
  Smartphone
} from 'lucide-react';
import { Button } from './ui/Button';
import { Badge } from './ui/Badge';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from './ui/Card';
import { Input } from './ui/Input';
import { Typography } from './ui/Typography';
import { 
  Dialog, 
  DialogContent, 
  DialogDescription, 
  DialogFooter, 
  DialogHeader, 
  DialogTitle, 
  DialogTrigger 
} from './ui/Dialog';
import { Tabs, TabsContent, TabsList, TabsTrigger } from './ui/Tabs';
import { Switch } from './ui/Switch';
import { Checkbox } from './ui/Checkbox';
import { Avatar, AvatarFallback, AvatarImage } from './ui/Avatar';
import { Progress } from './ui/Progress';
import { 
  Select, 
  SelectContent, 
  SelectGroup, 
  SelectItem, 
  SelectLabel, 
  SelectTrigger, 
  SelectValue 
} from './ui/Select';
import { Separator } from './ui/Separator';

import { 
  Tooltip, 
  TooltipContent, 
  TooltipProvider, 
  TooltipTrigger 
} from './ui/Tooltip';

interface DesignSystemScreenProps {
  onBack: () => void;
}

export function DesignSystemScreen({ onBack }: DesignSystemScreenProps) {
  const [progress, setProgress] = useState(65);

  return (
    <TooltipProvider>
      <div className="min-h-screen bg-rayon-surface p-6 pb-32 mobi-grid">
        <header className="flex items-center gap-4 mb-8 sticky top-0 z-50 bg-rayon-surface/80 backdrop-blur-xl py-4 -mx-6 px-6 border-b border-white/5">
          <button onClick={onBack} className="p-2 rounded-xl bg-white/5 hover:bg-white/10 transition-colors">
            <ArrowLeft size={20} />
          </button>
          <div className="flex-1">
            <Typography variant="h3">Design System</Typography>
            <Typography variant="small" className="opacity-50">v1.2.0 • Rayon x Mobi Hybrid</Typography>
          </div>
          <Tooltip>
            <TooltipTrigger asChild>
              <Badge variant="accent" className="cursor-help">Stable</Badge>
            </TooltipTrigger>
            <TooltipContent>
              <p>Production ready components</p>
            </TooltipContent>
          </Tooltip>
        </header>

      <div className="space-y-16 max-w-4xl mx-auto">
        {/* Colors */}
        <section className="space-y-6">
          <SectionHeader title="Colors" description="The core palette defining the brand identity." />
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-6">
            <ColorSwatch color="bg-rayon-primary" name="Primary" hex="#0047AB" />
            <ColorSwatch color="bg-rayon-accent-gold" name="Accent Gold" hex="#FFD700" />
            <ColorSwatch color="bg-rayon-surface" name="Surface" hex="#050505" />
            <ColorSwatch color="bg-rayon-surface-alt" name="Surface Alt" hex="#111111" />
            <ColorSwatch color="bg-rayon-success" name="Success" hex="#00FF00" />
            <ColorSwatch color="bg-rayon-warning" name="Warning" hex="#FFA500" />
            <ColorSwatch color="bg-rayon-danger" name="Danger" hex="#FF3B30" />
            <ColorSwatch color="bg-rayon-text-secondary" name="Muted" hex="#888888" />
          </div>
        </section>

        {/* Typography */}
        <section className="space-y-6">
          <SectionHeader title="Typography" description="Font scales and styles for clear information hierarchy." />
          <Card padding="lg" variant="glass">
            <div className="space-y-8">
              <div className="space-y-2">
                <Typography variant="label">Heading 1</Typography>
                <Typography variant="h1">The Future of Fan Finance</Typography>
              </div>
              <Separator />
              <div className="space-y-2">
                <Typography variant="label">Heading 2</Typography>
                <Typography variant="h2">Seamless Biometric Payments</Typography>
              </div>
              <Separator />
              <div className="space-y-2">
                <Typography variant="label">Heading 3</Typography>
                <Typography variant="h3">Rayon Sports Official Hub</Typography>
              </div>
              <Separator />
              <div className="space-y-2">
                <Typography variant="label">Lead Paragraph</Typography>
                <Typography variant="lead">A robust and comprehensive UI design system built for Rayon Sports x Mobi.fintech.</Typography>
              </div>
              <Separator />
              <div className="space-y-2">
                <Typography variant="label">Body Text</Typography>
                <Typography variant="p" className="mt-0">This is standard body text. It uses the Inter font family for maximum legibility and a modern feel. Perfect for long-form content and descriptions.</Typography>
              </div>
              <Separator />
              <div className="flex gap-12">
                <div className="space-y-2">
                  <Typography variant="label">Mobi Label</Typography>
                  <Typography variant="label" className="block">Transaction ID</Typography>
                </div>
                <div className="space-y-2">
                  <Typography variant="label">Mobi Value</Typography>
                  <Typography variant="value" className="block">#TX-8829-AF</Typography>
                </div>
              </div>
            </div>
          </Card>
        </section>

        {/* Buttons */}
        <section className="space-y-6">
          <SectionHeader title="Buttons" description="Interactive triggers for primary and secondary actions." />
          <div className="space-y-8">
            <div className="flex flex-wrap gap-4">
              <Button variant="primary">Primary Action</Button>
              <Button variant="accent">Accent Action</Button>
              <Button variant="secondary">Secondary</Button>
              <Button variant="outline">Outline</Button>
              <Button variant="ghost">Ghost</Button>
            </div>
            <div className="flex flex-wrap items-center gap-4">
              <Button size="sm">Small Button</Button>
              <Button size="md">Medium Button</Button>
              <Button size="lg">Large Button</Button>
              <Button size="icon"><Zap size={18} /></Button>
              <Button isLoading>Processing</Button>
            </div>
          </div>
        </section>

        {/* Overlays & Navigation */}
        <section className="space-y-6">
          <SectionHeader title="Overlays & Navigation" description="Complex components for state management and layout." />
          <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            {/* Dialog / Modal */}
            <Card className="flex flex-col justify-between">
              <CardHeader>
                <CardTitle>Dialogs</CardTitle>
                <CardDescription>Overlays for focused interactions.</CardDescription>
              </CardHeader>
              <CardContent>
                <Dialog>
                  <DialogTrigger asChild>
                    <Button variant="outline" className="w-full">Open Modal</Button>
                  </DialogTrigger>
                  <DialogContent>
                    <DialogHeader>
                      <DialogTitle>Confirm Transaction</DialogTitle>
                      <DialogDescription>
                        You are about to send 5,000 RWF to Rayon Sports Fan Club. This action cannot be undone.
                      </DialogDescription>
                    </DialogHeader>
                    <div className="py-4 space-y-4">
                      <div className="flex justify-between items-center p-4 rounded-2xl bg-white/5 border border-white/5">
                        <Typography variant="label">Amount</Typography>
                        <Typography variant="value">5,000 RWF</Typography>
                      </div>
                    </div>
                    <DialogFooter>
                      <Button variant="ghost">Cancel</Button>
                      <Button variant="primary">Confirm Payment</Button>
                    </DialogFooter>
                  </DialogContent>
                </Dialog>
              </CardContent>
            </Card>

            {/* Tabs */}
            <Card>
              <CardHeader>
                <CardTitle>Tabs</CardTitle>
                <CardDescription>Switch between related views.</CardDescription>
              </CardHeader>
              <CardContent>
                <Tabs defaultValue="account" className="w-full">
                  <TabsList className="w-full grid grid-cols-2">
                    <TabsTrigger value="account">Account</TabsTrigger>
                    <TabsTrigger value="security">Security</TabsTrigger>
                  </TabsList>
                  <TabsContent value="account">
                    <div className="p-4 rounded-2xl bg-white/5 border border-white/5 text-xs text-rayon-text-secondary">
                      Account settings and personal information.
                    </div>
                  </TabsContent>
                  <TabsContent value="security">
                    <div className="p-4 rounded-2xl bg-white/5 border border-white/5 text-xs text-rayon-text-secondary">
                      Security preferences and BioPay settings.
                    </div>
                  </TabsContent>
                </Tabs>
              </CardContent>
            </Card>
          </div>
        </section>

        {/* Form Elements */}
        <section className="space-y-6">
          <SectionHeader title="Form Elements" description="Inputs, toggles, and selectors for data entry." />
          <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <Card className="space-y-6">
              <Input label="Email Address" placeholder="alex@rayon.com" icon={<Mail size={18} />} />
              <Select>
                <SelectTrigger>
                  <SelectValue placeholder="Select Bank" />
                </SelectTrigger>
                <SelectContent>
                  <SelectGroup>
                    <SelectLabel>Commercial Banks</SelectLabel>
                    <SelectItem value="bk">Bank of Kigali</SelectItem>
                    <SelectItem value="bpr">BPR Bank</SelectItem>
                    <SelectItem value="im">I&M Bank</SelectItem>
                  </SelectGroup>
                </SelectContent>
              </Select>
            </Card>

            <Card className="space-y-6">
              <div className="flex items-center justify-between p-4 rounded-2xl bg-white/5 border border-white/5">
                <div className="space-y-0.5">
                  <Typography variant="small" className="text-white">BioPay Enabled</Typography>
                  <Typography variant="muted" className="text-[10px]">Use face ID for payments</Typography>
                </div>
                <Switch defaultChecked />
              </div>
              <div className="flex items-center space-x-3 px-1">
                <Checkbox id="terms" />
                <label htmlFor="terms" className="text-xs text-rayon-text-secondary leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70">
                  I agree to the terms and conditions
                </label>
              </div>
            </Card>
          </div>
        </section>

        {/* Feedback & Status */}
        <section className="space-y-6">
          <SectionHeader title="Feedback & Status" description="Visual cues for progress and system state." />
          <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <Card className="space-y-6">
              <div className="space-y-2">
                <div className="flex justify-between items-end">
                  <Typography variant="label">Savings Goal</Typography>
                  <Typography variant="value" className="text-rayon-primary">65%</Typography>
                </div>
                <Progress value={progress} />
              </div>
              <div className="flex gap-2">
                <Button size="sm" variant="outline" onClick={() => setProgress(Math.max(0, progress - 10))}>-10%</Button>
                <Button size="sm" variant="outline" onClick={() => setProgress(Math.min(100, progress + 10))}>+10%</Button>
              </div>
            </Card>

            <Card className="flex items-center gap-4">
              <Avatar className="h-16 w-16 border-2 border-rayon-primary">
                <AvatarImage src="https://picsum.photos/seed/user/200" />
                <AvatarFallback>AJ</AvatarFallback>
              </Avatar>
              <div className="flex-1">
                <Typography variant="large">Alex Johnson</Typography>
                <Typography variant="small" className="opacity-60">Gold Member • #8829</Typography>
                <div className="flex gap-2 mt-2">
                  <Badge variant="success" size="sm">Verified</Badge>
                  <Badge variant="primary" size="sm">Admin</Badge>
                </div>
              </div>
            </Card>
          </div>
        </section>

        {/* Badges Grid */}
        <section className="space-y-6">
          <SectionHeader title="Semantic Badges" description="Status indicators with semantic coloring." />
          <div className="flex flex-wrap gap-3">
            <Badge variant="primary">Primary</Badge>
            <Badge variant="accent">Accent</Badge>
            <Badge variant="success">Success</Badge>
            <Badge variant="warning">Warning</Badge>
            <Badge variant="danger">Danger</Badge>
            <Badge variant="secondary">Secondary</Badge>
            <Badge variant="outline">Outline</Badge>
          </div>
        </section>
      </div>
    </div>
  </TooltipProvider>
  );
}

function SectionHeader({ title, description }: { title: string, description: string }) {
  return (
    <div className="space-y-1">
      <Typography variant="h4" className="text-rayon-primary">{title}</Typography>
      <Typography variant="small" className="opacity-60">{description}</Typography>
    </div>
  );
}

function ColorSwatch({ color, name, hex }: { color: string, name: string, hex: string }) {
  return (
    <div className="space-y-3 group">
      <div className={`w-full aspect-square rounded-3xl ${color} border border-white/10 shadow-2xl group-hover:scale-105 transition-transform duration-500 relative overflow-hidden`}>
        <div className="absolute inset-0 bg-gradient-to-br from-white/10 to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
      </div>
      <div>
        <Typography variant="label" className="block text-white">{name}</Typography>
        <Typography variant="small" className="font-mono opacity-40 text-[9px]">{hex}</Typography>
      </div>
    </div>
  );
}
